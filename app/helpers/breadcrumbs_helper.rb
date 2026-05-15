module BreadcrumbsHelper
  def breadcrumbs(*crumbs)
    content_for(:breadcrumbs) do
      render "shared/breadcrumbs", crumbs:
    end
  end
end
