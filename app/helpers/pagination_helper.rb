# Pagination for the management index screens.
#
# These screens used to render an entire table. Two of them -- sessions and
# statistics -- grow without bound (statistics is an append-only series written
# by the ingestion pipeline), so they eventually stopped rendering at all.
#
# Hand-rolled rather than a gem: the app pins sprockets 3 and jquery-rails for
# asset-pipeline reasons (see the Gemfile notes), and a dependency is not worth
# adding to page a table.
module PaginationHelper
  PAGE_SIZE = 25

  # Renders prev/next links and a page-count line. Returns nil when everything
  # fits on one page, so single-page screens render exactly as before.
  #
  # +page+ and +pages+ are passed in rather than read from params, so this has
  # no dependency on where the request lives.
  def pagination_nav(total = @total, page = @page, pages = @pages, base_params = {})
    return if pages.nil? || pages <= 1

    parts = []
    parts << link_to('&laquo; Prev'.html_safe, url_for(base_params.merge(page: page - 1))) if page > 1
    parts << "Page #{page} of #{pages} (#{total} total)"
    parts << link_to('Next &raquo;'.html_safe, url_for(base_params.merge(page: page + 1))) if page < pages
    content_tag(:p, parts.join(' &middot; ').html_safe, class: 'pagination')
  end
end
