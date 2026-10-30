defmodule Ltix.Credo.SpecReferencesTest do
  use Credo.Test.Case

  alias Ltix.Credo.SpecReferences

  test "flags a spec reference that isn't a link on one line" do
    """
    defmodule Example do
      # See Sec §5.1.3 step 9
      def run, do: :ok

      # [Core §5.3.7](https://www.imsglobal.org/spec/lti/v1p3/
      # #roles-claim)
      def roles, do: []

      # [RFC 7515 §4.1.11][crit]
      def crit, do: nil
    end
    """
    |> to_source_file()
    |> run_check(SpecReferences)
    |> assert_issues_match([%{line_no: 2}, %{line_no: 5}, %{line_no: 9}])
  end

  test "flags a citation by section title that isn't a link" do
    """
    defmodule Example do
      # [Core, Roles claim]
      def roles, do: []

      # [AGS, Result service endpoint](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#result-service-endpoint), [AGS, Service endpoint]
      def endpoint, do: nil
    end
    """
    |> to_source_file()
    |> run_check(SpecReferences)
    |> assert_issues_match([%{line_no: 2}, %{line_no: 5}])
  end

  test "accepts inline links and references outside comments" do
    ~S'''
    defmodule Example do
      @moduledoc """
      URLs must not include a userinfo component (RFC 3986 §3.2.1).

          # See RFC 3986 §3.2.1
      """

      # [Sec §5.1.2](https://www.imsglobal.org/spec/security/v1p0/#id-token)
      # [Core, LTI Deployment ID claim](https://standards.1edtech.org/lti/specifications/core/lti-spec#lti-deployment-id-claim)
      # [Cert, Known "Bad" Payloads](https://standards.1edtech.org/lti/specifications/guides/conformance/conformance-guide#known-bad-payloads)
      def run, do: :ok
    end
    '''
    |> to_source_file()
    |> run_check(SpecReferences)
    |> refute_issues()
  end
end
