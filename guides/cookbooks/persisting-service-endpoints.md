# Persisting Service Endpoints

Service calls that happen outside an LTI launch need endpoint URLs that
were stored during one. Consider a mobile attendance app: the LTI launch
sets up the course, but grade posting happens later when students check
in on their phones. This cookbook shows what to persist and where, using
that app as a running example.

## Programmatic line items

The tool creates its own "Attendance" line item in the gradebook and
posts scores to it. It also syncs the roster so it can pair students'
mobile accounts with their LMS identities using the LIS data from
membership responses.

Both URLs live on the course, since they're context-scoped.

### Migration

```elixir
defmodule MyApp.Repo.Migrations.AddServiceEndpointsToCourses do
  use Ecto.Migration

  def change do
    alter table(:courses) do
      add :memberships_url, :string
      add :lineitems_url, :string
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
    belongs_to :registration, MyApp.Lti.Registration
    timestamps()
  end

  def changeset(course, attrs) do
    course
    |> cast(attrs, [:context_id, :title, :registration_id, :memberships_url, :lineitems_url])
    |> validate_required([:context_id, :registration_id])
    |> unique_constraint([:context_id, :registration_id])
  end
end
```

### Storing during launch

Extract the endpoint URLs in `create_course!/1`. Either claim may be
`nil` if the platform doesn't support that service. The upsert replaces
endpoint URLs on every launch, keeping them current if the platform
ever changes them.

```elixir
def create_course!(%Ltix.LaunchContext{claims: claims, registration: registration}) do
  attrs = %{
    context_id: claims.context.id,
    registration_id: registration.id,
    title: claims.context.title,
    memberships_url: claims.memberships_endpoint && claims.memberships_endpoint.context_memberships_url,
    lineitems_url: claims.ags_endpoint && claims.ags_endpoint.lineitems
  }

  %Course{}
  |> Course.changeset(attrs)
  |> Repo.insert!(
    on_conflict: {:replace, [:title, :memberships_url, :lineitems_url, :updated_at]},
    conflict_target: [:context_id, :registration_id],
    returning: true
  )
end
```

### Using stored endpoints

Sync the roster periodically to pair mobile accounts with LMS users:

```elixir
alias Ltix.LaunchClaims.MembershipsEndpoint

def sync_roster(course) do
  registration = get_registration(course)
  endpoint = MembershipsEndpoint.new(course.memberships_url)

  {:ok, client} = Ltix.MembershipsService.authenticate(registration,
    endpoint: endpoint
  )

  {:ok, members} = Ltix.MembershipsService.get_members(client)
  # Pair mobile accounts with LMS users using LIS data from members
end
```

Post a score to a line item the tool created earlier:

```elixir
alias Ltix.LaunchClaims.AgsEndpoint

def post_attendance(course, user_id) do
  registration = get_registration(course)
  endpoint = %AgsEndpoint{lineitems: course.lineitems_url}

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

## Coupled line items

Instead of creating line items programmatically, the instructor creates
one tool placement per class session: "Week 1", "Week 2", etc. The
platform pre-creates a grade column for each placement. The lineitem URL
for that column is resource-link-scoped (different per session), so it
needs its own schema.

### Migration

```elixir
defmodule MyApp.Repo.Migrations.CreateClassSessions do
  use Ecto.Migration

  def change do
    create table(:class_sessions) do
      add :resource_link_id, :string, null: false
      add :title, :string
      add :lineitem_url, :string
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
    belongs_to :course, MyApp.Course
    timestamps()
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:resource_link_id, :title, :lineitem_url, :course_id])
    |> validate_required([:resource_link_id, :course_id])
    |> unique_constraint([:resource_link_id, :course_id])
  end
end
```

### Storing during launch

```elixir
def create_class_session!(%Ltix.LaunchContext{claims: claims}, course) do
  attrs = %{
    resource_link_id: claims.resource_link.id,
    title: claims.resource_link.title,
    lineitem_url: claims.ags_endpoint && claims.ags_endpoint.lineitem,
    course_id: course.id
  }

  %ClassSession{}
  |> ClassSession.changeset(attrs)
  |> Repo.insert!(
    on_conflict: {:replace, [:title, :lineitem_url, :updated_at]},
    conflict_target: [:resource_link_id, :course_id],
    returning: true
  )
end
```

### Using stored endpoints

When a student checks in for a specific session, post the score directly
to that session's grade column:

```elixir
alias Ltix.LaunchClaims.AgsEndpoint

def post_check_in(session, user_id) do
  course = Repo.preload(session, :course).course
  registration = get_registration(course)
  endpoint = %AgsEndpoint{lineitem: session.lineitem_url}

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

See [Advantage Services](../advantage-services.md) for an overview of
token management, [Syncing Grades in the Background](background-grade-sync.md)
for Oban worker patterns, and
[Token Caching and Reuse](token-caching-and-reuse.md) for batch
refreshing across courses.
