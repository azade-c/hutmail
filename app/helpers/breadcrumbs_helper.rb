module BreadcrumbsHelper
  def breadcrumb(*crumbs)
    content_for(:breadcrumbs) do
      render "shared/breadcrumbs", crumbs:
    end
  end
end
