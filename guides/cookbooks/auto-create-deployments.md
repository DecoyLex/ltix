# Auto-creating Deployments on First Launch

In the standard LTI flow, registrations and deployments are both created
out-of-band before the first launch. But many tools don't need
per-deployment configuration. They care about the platform (registration)
but treat deployments as bookkeeping. For these tools, you can
auto-create deployments the first time a new `deployment_id` appears in
a launch.

This works because `get_deployment/2` runs after JWT signature
verification and nonce validation, so the `deployment_id` is already
trusted by the time your adapter sees it.

<!-- tabs-open -->

### Storage adapter

The simplest approach: make `get_deployment/2` upsert instead of just
querying. The first launch creates the deployment row; subsequent
launches find it. No controller changes needed.

```elixir
@impl true
def get_deployment(%Ltix.Registration{} = reg, deployment_id) do
  registration_id = get_registration_id(reg)

  %PlatformDeployment{registration_id: registration_id, deployment_id: deployment_id}
  |> Repo.insert(on_conflict: :nothing, conflict_target: [:registration_id, :deployment_id])

  case Repo.get_by(PlatformDeployment,
         registration_id: registration_id,
         deployment_id: deployment_id
       ) do
    nil -> {:error, :not_found}
    record -> {:ok, record}
  end
end
```

The insert-then-select pattern handles the race condition where two
concurrent launches for the same new deployment both call
`get_deployment/2` at the same time. `on_conflict: :nothing` means the
second insert silently succeeds without duplicating the row, and both
calls find the same record on the subsequent select.

> #### Migration {: .tip}
>
> Your `platform_deployments` table needs a unique index for the
> upsert's conflict target:
>
> ```elixir
> create unique_index(:platform_deployments, [:registration_id, :deployment_id])
> ```

### Controller

If deployments carry meaning in your domain (per-deployment settings,
onboarding flows, approval steps), handle creation in the controller
instead. This lets you show a registration form, collect extra
information, or require admin approval before the deployment is active.

```elixir
def launch(conn, params) do
  state = get_session(conn, :lti_state)

  case Ltix.handle_callback(params, state) do
    {:ok, context} ->
      conn
      |> delete_session(:lti_state)
      |> render(:launch, context: context)

    {:error, %Ltix.Errors.Invalid.DeploymentNotFound{deployment_id: id}} ->
      # Create the deployment, then ask the user to re-launch.
      # We can't retry handle_callback here because the nonce was
      # already consumed (see note below).
      MyApp.Deployments.create!(id)

      conn
      |> delete_session(:lti_state)
      |> render(:deployment_created,
        message: "Setup complete. Return to your LMS and launch again."
      )

    {:error, error} ->
      conn
      |> put_status(400)
      |> text("Launch failed: #{Exception.message(error)}")
  end
end
```

For an onboarding flow where you need to collect information before
creating the deployment:

```elixir
{:error, %Ltix.Errors.Invalid.DeploymentNotFound{deployment_id: id}} ->
  conn
  |> put_session(:pending_deployment_id, id)
  |> delete_session(:lti_state)
  |> redirect(to: ~p"/lti/onboard")
```

> #### Nonce is consumed before deployment lookup {: .warning}
>
> `handle_callback/3` validates and consumes the nonce before looking
> up the deployment. When the call fails with `DeploymentNotFound`, the
> nonce is already gone. You cannot retry `handle_callback/3` with the
> same params. The user must re-launch from the platform.

<!-- tabs-close -->

## Which approach to use

| | Storage adapter | Controller |
|---|---|---|
| Best for | Deployments are bookkeeping | Deployments carry domain meaning |
| Controller changes | None | Match on `DeploymentNotFound` |
| User experience | Seamless, first launch just works | Can show onboarding UI |
| Complexity | Low | Medium |
