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
class Api::V1::ErrataController < Api::V1::ApiController
  respond_to :json

  resource_description do
    error :code => 401, :desc => N_("Unauthorized")
    error :code => 404, :desc => N_("Not found")

    api_version 'v1'
  end

  before_filter :find_environment, :only => [:index]
  before_filter :find_repository
  before_filter :find_erratum, :except => [:index]
  before_filter :authorize

  def rules
    env_readable = lambda { @environment.contents_readable? }
    readable     = lambda { @repo.environment.contents_readable? && @repo.product.readable? }
    {
        :index => env_readable,
        :show  => readable,
    }
  end

  api :GET, "/errata", N_("List errata")
  api :GET, "/repositories/:repository_id/errata", N_("List errata")
  description N_("Either :repoid or :product_id is required.")
  error :code => 400, :desc => N_("Repo id or environment must be provided")
  param :environment_id, :number, :desc => N_("Id of environment containing the errata.")
  param :product_id, :number, :desc => N_("The product which contains the errata.")
  param :repoid, :number, :desc => N_("Id of repository containing the errata.")
  param :severity, String, :desc => N_("Severity of errata. Usually one of: Critical, Important, Moderate, Low. Case insensitive.")
  param :type, String, :desc => N_("Type of errata. Usually one of: security, bugfix, enhancement. Case insensitive.")
  def index
    filter = params.symbolize_keys.slice(:repoid, :repository_id, :product_id, :environment_id, :type, :severity)
    unless filter[:repoid] || filter[:repository_id] || filter[:environment_id]
      fail HttpErrors::BadRequest.new(_("Repo ID or environment must be provided"))
    end
    render :json => Errata.filter(filter)
  end

  api :GET, "/repositories/:repository_id/errata/:id", N_("Show an erratum")
  def show
    render :json => @erratum
  end

  private

  def find_environment
    if params.key?(:environment_id)
      @environment = KTEnvironment.find(params[:environment_id])
      fail HttpErrors::NotFound, _("Couldn't find environment '%s'") % params[:environment_id] if @environment.nil?
    elsif params.key?(:repoid)
      @repo = Repository.find(params[:repoid])
      fail HttpErrors::NotFound, _("Couldn't find repository '%s'") % params[:repoid] if @repo.nil?
      @environment = @repo.environment
    end
    @environment
  end

  def find_repository
    if params.key?(:repository_id)
      @repo = Repository.find(params[:repository_id])
      fail HttpErrors::NotFound, _("Couldn't find repository '%s'") % params[:repository_id] if @repo.nil?
      @environment ||= @repo.environment
    end
    @repo
  end

  def find_erratum
    @erratum = Errata.find_by_errata_id(params[:id])
    fail HttpErrors::NotFound, _("Erratum with id '%s' not found") % params[:id] if @erratum.nil?
    # and check ownership of it
    fail HttpErrors::NotFound, _("Erratum '%s' not found within the repository") % params[:id] unless @erratum.repoids.include? @repo.pulp_id
    @erratum
  end
end
end
