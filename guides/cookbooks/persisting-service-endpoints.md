# Persisting Service Endpoints

Service calls that happen outside an LTI launch need endpoint URLs that were stored during one. Consider a mobile attendance app. The LTI launch sets up the course, but grade posting happens later when students check in on their phones. This cookbook shows what to persist and where, using that app as a running example.

## Programmatic line items

The tool creates its own "Attendance" line item in the gradebook and posts scores to it. It also syncs the roster so it can pair students' mobile accounts with their platform identities using the LIS data from membership responses.

Both URLs are context-scoped, so store them on the course. The grade service also needs the scopes from the launch claim, and the line item URL the platform returns when the tool creates its line item.

### Migration

```elixir
defmodule MyApp.Repo.Migrations.AddServiceEndpointsToCourses do
  use Ecto.Migration

  def change do
    alter table(:courses) do
      add :memberships_url, :string
      add :lineitems_url, :string
      add :ags_scopes, {:array, :string}
      add :attendance_line_item_url, :string
    end
  end
end
```

### Schema

```elixir
# lib/my_app/course.ex
defmodule MyApp.Course do
  use Ecto.Schema
  import Ecto.Changeset

  schema "courses" do
    field :context_id, :string
    field :title, :string
    field :memberships_url, :string
    field :lineitems_url, :string
    field :ags_scopes, {:array, :string}
    field :attendance_line_item_url, :string
    belongs_to :registration, MyApp.Lti.Registration
    timestamps()
  end

  def changeset(course, attrs) do
    course
    |> cast(attrs, [
      :context_id,
      :title,
      :registration_id,
      :memberships_url,
      :lineitems_url,
      :ags_scopes,
      :attendance_line_item_url
    ])
    |> validate_required([:context_id, :registration_id])
    |> unique_constraint([:context_id, :registration_id])
  end
end
```

### Storing during launch

Extract the endpoint URLs in `create_course!/1`. Either claim may be `nil` if the platform doesn't support that service. The upsert replaces endpoint URLs on every launch, keeping them current if the platform ever changes them.

```elixir
def create_course!(%Ltix.Launch{claims: %{context: context}} = launch) do
  memberships = Ltix.Launch.get_endpoint(launch, Ltix.MembershipsService)
  grades = Ltix.Launch.get_endpoint(launch, Ltix.GradeService)

  attrs = %{
    context_id: context.id,
    registration_id: launch.source_registration.id,
    title: context.title,
    memberships_url: memberships && memberships.context_memberships_url,
    lineitems_url: grades && grades.line_items,
    ags_scopes: grades && grades.scopes
  }

  %Course{}
  |> Course.changeset(attrs)
  |> Repo.insert!(
    on_conflict: {:replace, [:title, :memberships_url, :lineitems_url, :ags_scopes, :updated_at]},
    conflict_target: [:context_id, :registration_id],
    returning: true
  )
end
```

Create the attendance line item once, during the first launch, and store its URL.

```elixir
def ensure_attendance_line_item!(course, launch) do
  if course.attendance_line_item_url do
    course
  else
    {:ok, client} = Ltix.GradeService.authenticate(launch)

    {:ok, item} = Ltix.GradeService.create_line_item(client,
      label: "Attendance",
      score_maximum: 1,
      tag: "attendance"
    )

    course
    |> Course.changeset(%{attendance_line_item_url: item.id})
    |> Repo.update!()
  end
end
```

### Using stored endpoints

Sync the roster periodically to pair mobile accounts with platform users.

```elixir
def sync_roster(course) do
  registration = get_registration(course)
  endpoint = Ltix.MembershipsService.Endpoint.new!(course.memberships_url)

  {:ok, client} = Ltix.MembershipsService.authenticate(registration,
    endpoint: endpoint
  )

  {:ok, members} = Ltix.MembershipsService.list_members(client)
  # Pair mobile accounts with platform users using LIS data from members
end
```

Post a score to the line item the tool created earlier.

```elixir
def post_attendance(course, user_id) do
  registration = get_registration(course)

  endpoint =
    Ltix.GradeService.Endpoint.new!(line_items: course.lineitems_url, scopes: course.ags_scopes)

  {:ok, client} = Ltix.GradeService.authenticate(registration,
    endpoint: endpoint
  )

  {:ok, score} = Ltix.GradeService.Score.new(
    user_id: user_id,
    score_given: 1,
    score_maximum: 1,
    activity_progress: :completed,
    grading_progress: :fully_graded
  )

  :ok = Ltix.GradeService.post_score(client, score,
    line_item: course.attendance_line_item_url
  )
end
```

## Coupled line items

With coupled line items, the instructor creates one resource link per class session, such as "Week 1" and "Week 2". The platform creates a line item for each resource link. Its URL and scopes are specific to the resource link, so store them in a separate schema.

### Migration

```elixir
defmodule MyApp.Repo.Migrations.CreateClassSessions do
  use Ecto.Migration

  def change do
    create table(:class_sessions) do
      add :resource_link_id, :string, null: false
      add :title, :string
      add :lineitem_url, :string
      add :ags_scopes, {:array, :string}
      add :course_id, references(:courses), null: false
      timestamps()
    end

    create unique_index(:class_sessions, [:resource_link_id, :course_id])
  end
end
```

### Schema

```elixir
# lib/my_app/class_session.ex
defmodule MyApp.ClassSession do
  use Ecto.Schema
  import Ecto.Changeset

  schema "class_sessions" do
    field :resource_link_id, :string
    field :title, :string
    field :lineitem_url, :string
    field :ags_scopes, {:array, :string}
    belongs_to :course, MyApp.Course
    timestamps()
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:resource_link_id, :title, :lineitem_url, :ags_scopes, :course_id])
    |> validate_required([:resource_link_id, :course_id])
    |> unique_constraint([:resource_link_id, :course_id])
  end
end
```

### Storing during launch

```elixir
def create_class_session!(%Ltix.Launch{claims: claims} = launch, course) do
  grades = Ltix.Launch.get_endpoint(launch, Ltix.GradeService)

  attrs = %{
    resource_link_id: claims.resource_link.id,
    title: claims.resource_link.title,
    lineitem_url: grades && grades.line_item,
    ags_scopes: grades && grades.scopes,
    course_id: course.id
  }

  %ClassSession{}
  |> ClassSession.changeset(attrs)
  |> Repo.insert!(
    on_conflict: {:replace, [:title, :lineitem_url, :ags_scopes, :updated_at]},
    conflict_target: [:resource_link_id, :course_id],
    returning: true
  )
end
```

### Using stored endpoints

When a student checks in for a specific session, post the score directly to that session's line item.

```elixir
def post_check_in(session, user_id) do
  course = Repo.preload(session, :course).course
  registration = get_registration(course)
  endpoint = Ltix.GradeService.Endpoint.new!(line_item: session.lineitem_url, scopes: session.ags_scopes)

  {:ok, client} = Ltix.GradeService.authenticate(registration,
    endpoint: endpoint
  )

  {:ok, score} = Ltix.GradeService.Score.new(
    user_id: user_id,
    score_given: 1,
    score_maximum: 1,
    activity_progress: :completed,
    grading_progress: :fully_graded
  )

  :ok = Ltix.GradeService.post_score(client, score)
end
```

If your launches pass `plugins:` to `Ltix.handle_callback/3`, pass the same plugins to `authenticate/2` in these functions.

See [Advantage Services](../advantage-services.md) for an overview of token management, [Syncing Grades in the Background](background-grade-sync.md) for Oban worker patterns, and [Token Caching and Reuse](token-caching-and-reuse.md) for batch refreshing across courses.
