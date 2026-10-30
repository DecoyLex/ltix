# Specs

Local Markdown copies of the LTI specs, for reading and searching. Cite the live pages, as the Spec references section of [CODING_STANDARDS.md](../CODING_STANDARDS.md) describes.

## Converting a spec page

These copies came from the imsglobal.org spec pages. Each page is a Drupal page with the spec in `div.field-item.even`. Extract that element with BeautifulSoup, convert it with a small script of your own, then clean up the result. trafilatura drops code blocks, and pandoc keeps the highlighting spans and self-link anchors, so neither works alone.
