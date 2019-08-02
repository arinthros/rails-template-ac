class NotificationsController < ApplicationController
  before_action :authenticate_person!

  def index
    @notifications = current_person.notifications
  end
end
