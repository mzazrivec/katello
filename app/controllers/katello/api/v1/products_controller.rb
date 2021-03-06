#
# Copyright 2014 Red Hat, Inc.
#
# This software is licensed to you under the GNU General Public
# License as published by the Free Software Foundation; either version
# 2 of the License (GPLv2) or (at your option) any later version.
# There is NO WARRANTY for this software, express or implied,
# including the implied warranties of MERCHANTABILITY,
# NON-INFRINGEMENT, or FITNESS FOR A PARTICULAR PURPOSE. You should
# have received a copy of GPLv2 along with this software; if not, see
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt.

module Katello
class Api::V1::ProductsController < Api::V1::ApiController
  respond_to :json
  before_filter :find_optional_organization, :only => [:index, :repositories, :show, :update, :destroy, :set_sync_plan, :remove_sync_plan]
  before_filter :find_environment, :only => [:index, :repositories]
  before_filter :find_content_view, :only => [:repositories]
  before_filter :find_product, :only => [:repositories, :show, :update, :destroy, :set_sync_plan, :remove_sync_plan]
  before_filter :verify_presence_of_organization_or_environment, :only => [:index]
  before_filter :authorize

  resource_description do
    api_version 'v1'
  end

  def rules
    index_test = lambda { Product.any_readable?(@organization) }
    read_test  = lambda { @product.readable? }
    edit_test  = lambda { @product.editable? }
    repo_test  = lambda { Product.any_readable?(@organization) }

    {
        :index            => index_test,
        :show             => read_test,
        :update           => edit_test,
        :destroy          => edit_test,
        :repositories     => repo_test,
        :set_sync_plan    => edit_test,
        :remove_sync_plan => edit_test
    }
  end

  def param_rules
    {
        :update => { :product => [:description, :gpg_key_name, :recursive] }
    }
  end

  def_param_group :product do
    param :product, Hash, :required => true, :action_aware => true do
      param :gpg_key_name, :identifier, :desc => N_("identifier of the gpg key")
      param :description, String, :desc => N_("Product description")
    end
  end

  api :GET, "/organizations/:organization_id/products/:id", N_("Show a product")
  param :organization_id, :number, :desc => N_("organization identifier")
  param :id, :number, :desc => N_("product numeric identifier")
  def show
    respond
  end

  api :PUT, "/organizations/:organization_id/products/:id", N_("Update a product")
  param :organization_id, :number, :desc => N_("organization identifier")
  param :id, :number, :desc => N_("product numeric identifier")
  param_group :product
  param :product, Hash do
    param :recursive, :bool, :desc => N_("set to true to recursive update gpg key")
  end
  def update
    fail HttpErrors::BadRequest, _("Red Hat products cannot be updated.") if @product.redhat?
    @product.gpg_key_name = params[:product][:gpg_key_name] unless params[:product][:gpg_key_name].nil? # not .blank?
    @product.update_attributes!(params[:product].slice(:description))
    if params[:product][:recursive]
      @product.reset_repo_gpgs!
    end
    respond
  end

  api :GET, "/environments/:environment_id/products", N_("List products in an environment")
  api :GET, "/organizations/:organization_id/products", N_("List all products in an organization")
  param :organization_id, :number, :desc => N_("organization identifier")
  param :name, :identifier, :desc => N_("product identifier")
  param :include_marketing, :bool, :desc => N_("include marketing products in results")
  def index
    query_params.delete(:organization_id)
    query_params.delete(:environment_id)
    query_params[:type] = "Product" unless query_params.delete(:include_marketing)

    products = Product.all_readable(@organization)
    respond :collection => products.select("products.*, providers.name AS provider_name").joins(:provider).where(query_params).all
  end

  api :DELETE, "/organizations/:organization_id/products/:id", N_("Destroy a product")
  param :organization_id, :number, :desc => N_("organization identifier")
  param :id, :number, :desc => N_("product numeric identifier")
  def destroy
    @product.destroy
    respond :message => _("Deleted product '%s'") % params[:id]
  end

  api :GET, "/environments/:environment_id/products/:id/repositories"
  api :GET, "/organizations/:organization_id/products/:id/repositories"
  api :GET, "/organizations/:organization_id/products/:id/repositories"
  param :organization_id, :number, :desc => N_("organization identifier")
  param :environment_id, :identifier, :desc => N_("environment identifier")
  param :id, :number, :desc => N_("product numeric identifier")
  param :name, :identifier, :desc => N_("repository identifier")
  param :content_view_id, :identifier, :desc => N_("find repos in content view instead of default content view")
  def repositories
    if !@environment.library? && @content_view.nil?
      fail HttpErrors::BadRequest,
            _("Cannot retrieve repos from non-library environment '%s' without a content view.") % @environment.name
    end

    respond_for_index :collection => @product.repos(@environment, @content_view).
        where(query_params.slice(:name))
  end

  api :POST, "/organizations/:organization_id/products/:id/sync_plan", N_("Assign sync plan to product")
  param :organization_id, :number, :desc => N_("organization identifier")
  param :id, :number, :desc => N_("product numeric identifier")
  param :plan_id, :number, :desc => N_("Plan numeric identifier")
  def set_sync_plan
    @product.sync_plan = SyncPlan.find(params[:plan_id])
    @product.save!
    respond_for_status :message => _("Synchronization plan assigned.")
  end

  api :DELETE, "/organizations/:organization_id/products/:id/sync_plan", N_("Delete assignment sync plan and product")
  param :organization_id, :number, :desc => N_("organization identifier")
  param :id, :number, :desc => N_("product numeric identifier")
  param :plan_id, :number, :desc => N_("Plan numeric identifier")
  def remove_sync_plan
    @product.sync_plan = nil
    @product.save!
    respond_for_status :message => _("Synchronization plan assigned.")
  end

  private

  def find_product
    fail _("Neither organization nor environment has been provided.") if @organization.nil?
    @product = Product.find_by_cp_id(params[:id], @organization)
    fail HttpErrors::NotFound, _("Couldn't find product with id '%s'") % params[:id] if @product.nil?
  end

  def find_environment
    if params[:environment_id].nil?
      @environment = @organization.library unless @organization.nil?
      @environment = @product.organization.library unless @product.nil?
    else
      @environment = KTEnvironment.find_by_id(params[:environment_id])
      fail HttpErrors::NotFound, _("Couldn't find environment '%s'") % params[:environment_id] if @environment.nil?
    end
    @organization ||= @environment.organization if @environment
  end

  def find_content_view
    if params[:content_view_id]
      @content_view = ContentView.readable.find(params[:content_view_id])
    end
  end

  def verify_presence_of_organization_or_environment
    return if @organization || @environment
    fail HttpErrors::BadRequest, _("Either organization ID or environment ID needs to be specified")
  end

end
end
