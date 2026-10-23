defmodule Ltix.MembershipsService.PropertiesTest do
  use ExUnit.Case, async: true

  import MembershipsServiceFixtures

  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Unknown.InvalidPluginSet
  alias Ltix.MembershipsService
  alias Ltix.MembershipsService.Member
  alias Ltix.MembershipsService.MembershipContainer

  alias Ltix.PluginSet.Conflict
  alias TestPlugins.Modules
  alias TestPlugins.OtherStudentNumber
  alias TestPlugins.StudentNumber
  alias TestPlugins.Term

  @student_number "https://vendor.example.com/student_number"
  @unrecognized "https://platform.example.com/nickname"

  # The conflict, with each party replaced by its entry's module.
  defp modules(%Conflict{parties: parties} = conflict),
    do: %{conflict | parties: Enum.map(parties, & &1.module)}

  describe "member properties" do
    test "a declared property is parsed into extensions and an undeclared one into unrecognized" do
      client = create_client(plugins: [{Modules, add: [StudentNumber]}])

      member =
        Map.merge(member("user-1"), %{
          @student_number => %{"value" => "s-42"},
          @unrecognized => "JJ"
        })

      assert {{:ok, %{members: [listed]}}, {:ok, [streamed]}} = list_and_stream(client, [member])

      for member <- [listed, streamed] do
        assert member.extensions == %{student_number: %{value: "s-42"}}
        assert member.unrecognized == %{@unrecognized => "JJ"}
      end
    end

    test "members and membership containers take anonymous properties" do
      build = fn plugin ->
        plugin
        |> Member.add_property(
          property: @student_number,
          name: :student_number,
          schema: Zoi.string()
        )
        |> MembershipContainer.add_property(
          property: "https://vendor.example.com/term",
          name: :term
        )
      end

      client = create_client(plugins: [{Modules, build: build}])
      member = Map.put(member("user-1"), @student_number, "s-42")

      assert {{:ok, %{members: [listed]}}, {:ok, [streamed]}} = list_and_stream(client, [member])

      for member <- [listed, streamed],
          do: assert(member.extensions == %{student_number: "s-42"})
    end

    test "a property value that fails to parse fails the call" do
      client = create_client(plugins: [{Modules, add: [StudentNumber]}])

      member = Map.put(member("user-1"), @student_number, "s-42")

      assert {{:error, listed}, {:error, streamed}} = list_and_stream(client, [member])

      for error <- [listed, streamed] do
        assert %InvalidClaim{
                 claim: "member.https://vendor.example.com/student_number",
                 value: "s-42",
                 message: "must be an object with a value"
               } = error
      end
    end

    test "plugins: replaces the client's plugin set" do
      client = create_client(plugins: [{Modules, add: [StudentNumber]}])
      member = Map.put(member("user-1"), @student_number, %{"value" => "s-42"})

      assert {{:ok, %{members: [listed]}}, {:ok, [streamed]}} =
               list_and_stream(client, [member], plugins: [])

      for member <- [listed, streamed] do
        assert member.extensions == %{}
        assert member.unrecognized == %{@student_number => %{"value" => "s-42"}}
      end
    end

    test "two modules declaring one membership container property are a conflict" do
      client = create_client(plugins: [])

      assert {:error, %InvalidPluginSet{conflicts: [conflict]}} =
               MembershipsService.list_members(client,
                 plugins: [{Modules, add: [Term, TestPlugins.OtherTerm]}]
               )

      assert modules(conflict) == %Conflict{
               parties: [Term, TestPlugins.OtherTerm],
               reason:
                 ~s(both declare the property "https://vendor.example.com/term" on Ltix.MembershipsService.MembershipContainer)
             }
    end

    test "two modules declaring one member property are a conflict" do
      client = create_client(plugins: [])

      assert {:error, %InvalidPluginSet{conflicts: [conflict]}} =
               MembershipsService.list_members(client,
                 plugins: [
                   {Modules, name: "Numbers", add: [StudentNumber, OtherStudentNumber]}
                 ]
               )

      assert modules(conflict) == %Conflict{
               parties: [StudentNumber, OtherStudentNumber],
               reason:
                 ~s(both declare the property "#{@student_number}" on Ltix.MembershipsService.Member)
             }
    end
  end

  describe "membership container properties" do
    test "a declared property is parsed into extensions" do
      client = create_client(plugins: [{Modules, add: [Term]}])

      body =
        Map.merge(container(1), %{
          "https://vendor.example.com/term" => %{"name" => "Fall"},
          @unrecognized => "Course"
        })

      stub_pages(1, body)

      assert {:ok, roster} = MembershipsService.list_members(client)
      assert roster.extensions == %{term: %{name: "Fall"}}
      assert roster.unrecognized == %{@unrecognized => "Course"}
    end

    test "the context's properties are parsed as a launch's context claim's are" do
      client = create_client(plugins: [{Modules, add: [TestPlugins.Section]}])
      context = %{"id" => "course", "https://vendor.example.com/section" => "A"}
      stub_pages(1, Map.put(container(1), "context", context))

      assert {:ok, roster} = MembershipsService.list_members(client)
      assert roster.context.extensions == %{section: "A"}
    end
  end
end
