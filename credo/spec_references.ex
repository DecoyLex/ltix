defmodule Ltix.Credo.SpecReferences do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      A spec reference in a comment is an inline link to the section, on one
      line.

          # [Core, LTI Deployment ID claim](https://standards.1edtech.org/lti/specifications/core/lti-spec#lti-deployment-id-claim)
          # [Sec §5.1.2](https://www.imsglobal.org/spec/security/v1p0/#id-token)
      """
    ]

  @comment ~r/^\s*#(?<comment>.*)$/
  @link ~r/\[[^\]]*\]\(https?:\/\/[^\s)]+\)/

  # A section number, or a citation of a 1EdTech spec by section title.
  @reference ~r/§|\[(Core|AGS|DL|NRPS|Cert|Sec)[ ,]/

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    context = Context.build(source_file, params, __MODULE__)
    lines = String.split(Credo.Code.clean_charlists_strings_and_sigils(source_file), "\n")

    for {line, line_no} <- Enum.with_index(lines, 1),
        %{"comment" => comment} <- [Regex.named_captures(@comment, line)],
        String.replace(comment, @link, "") =~ @reference do
      format_issue(context,
        message: "Link a spec reference inline, on one line.",
        line_no: line_no
      )
    end
  end
end
