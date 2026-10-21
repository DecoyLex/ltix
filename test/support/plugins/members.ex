defmodule TestPlugins.StudentNumber do
  @moduledoc false
  # A member property, as an atom-keyed map.
  use Ltix.MembershipsService.Member,
    property: "https://vendor.example.com/student_number",
    name: :student_number

  @impl Ltix.Property
  def parse(%{"value" => number}, _opts), do: {:ok, %{value: number}}
  def parse(_json, _opts), do: {:error, "must be an object with a value"}

  @impl Ltix.Property
  def serialize(%{value: number}, _opts), do: %{"value" => number}
end

defmodule TestPlugins.OtherStudentNumber do
  @moduledoc false
  # Declares the property `TestPlugins.StudentNumber` declares.
  use Ltix.MembershipsService.Member,
    property: "https://vendor.example.com/student_number",
    name: :other_student_number
end

defmodule TestPlugins.Term do
  @moduledoc false
  # A membership container property, as an atom-keyed map.
  use Ltix.MembershipsService.MembershipContainer,
    property: "https://vendor.example.com/term",
    name: :term

  @impl Ltix.Property
  def parse(%{"name" => name}, _opts), do: {:ok, %{name: name}}

  @impl Ltix.Property
  def serialize(%{name: name}, _opts), do: %{"name" => name}
end

defmodule TestPlugins.Section do
  @moduledoc false
  # A property of the context claim, which membership containers have too.
  use Ltix.Claims.Context,
    property: "https://vendor.example.com/section",
    name: :section
end

defmodule TestPlugins.OtherTerm do
  @moduledoc false
  # Declares the membership container property `TestPlugins.Term` declares.
  use Ltix.MembershipsService.MembershipContainer,
    property: "https://vendor.example.com/term",
    name: :other_term
end
