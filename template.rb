require "fileutils"
require "shellwords"

# Copied from: https://github.com/mattbrictson/rails-template
# Add this template directory to source_paths so that Thor actions like
# copy_file and template resolve against our source files. If this file was
# invoked remotely via HTTP, that means the files are not present locally.
# In that case, use `git clone` to download them to a local temporary dir.
def add_template_repository_to_source_path
  if __FILE__ =~ %r{\Ahttps?://}
    require "tmpdir"
    source_paths.unshift(tempdir = Dir.mktmpdir("rails-template-ac-"))
    at_exit { FileUtils.remove_entry(tempdir) }
    git clone: [
      "--quiet",
      "https://github.com/arinthros/rails-template-ac.git",
      tempdir
    ].map(&:shellescape).join(" ")

    if (branch = __FILE__[%r{rails-template-ac/(.+)/template.rb}, 1])
      Dir.chdir(tempdir) { git checkout: branch }
    end
  else
    source_paths.unshift(File.dirname(__FILE__))
  end
end

def rails_version
  @rails_version ||= Gem::Version.new(Rails::VERSION::STRING)
end

def add_gems
  gem 'administrate', github: "thoughtbot/administrate"
  gem 'bootstrap', '~> 4.3', '>= 4.3.1'
  gem 'devise', '~> 4.6', '>= 4.6.2'
  gem 'devise-bootstrapped', github: 'excid3/devise-bootstrapped', branch: 'bootstrap4'
  gem 'devise_masquerade', '~> 0.6.5'
  gem 'font-awesome-sass', '~> 5.9', '>= 5.9.0'
  gem 'friendly_id', '~> 5.2', '>= 5.2.5'
  gem 'gravatar_image_tag', github: 'mdeering/gravatar_image_tag'
  gem 'name_of_person', '~> 1.1', '>= 1.1.1'
  gem 'sidekiq', '~> 5.2', '>= 5.2.7'
  gem 'whenever', require: false

end

def set_application_name
  # Add Application Name to Config
  environment "config.application_name = Rails.application.class.module_parent_name"

  # Announce the account where he can change the application name in the future.
  puts "You can change application name inside: ./config/application.rb"
end

def add_accounts
  # Install Devise
  generate "devise:install"

  # Configure Devise
  environment "config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }",
              env: 'development'
  route "root to: 'home#index'"

  # Devise notices are installed via Bootstrap
  generate "devise:views:bootstrapped"

  # Create Devise Account
  generate :devise, "Account",
           "first_name",
           "last_name",
           "admin:boolean"

  # Set admin default to false
  in_root do
    migration = Dir.glob("db/migrate/*").max_by{ |f| File.mtime(f) }
    gsub_file migration, /:admin/, ":admin, default: false"
  end

  if Gem::Requirement.new("> 6.0.0.rc2").satisfied_by? rails_version
    gsub_file "config/initializers/devise.rb",
      /  # config.secret_key = .+/,
      "  config.secret_key = Rails.application.credentials.secret_key_base"
  end

  # Add Devise masqueradable to accounts
  inject_into_file("app/models/account.rb", "masqueradable, :", after: "devise :")
end


def add_javascript
  run "yarn add expose-loader jquery popper.js bootstrap data-confirm-modal local-time"

  content = <<-JS
const webpack = require('webpack')
environment.plugins.append('Provide', new webpack.ProvidePlugin({
  $: 'jquery',
  jQuery: 'jquery',
  Rails: '@rails/ujs'
}))
  JS

  insert_into_file 'config/webpack/environment.js', content + "\n", before: "module.exports = environment"
end

def copy_templates
  remove_file "app/assets/stylesheets/application.css"

  copy_file "Procfile"
  copy_file "Procfile.dev"
  copy_file ".foreman"

  directory "app", force: true
  directory "config", force: true
  directory "lib", force: true

  route "get '/terms', to: 'home#terms'"
  route "get '/privacy', to: 'home#privacy'"
end

def add_sidekiq
  environment "config.active_job.queue_adapter = :sidekiq"

  insert_into_file "config/routes.rb",
    "require 'sidekiq/web'\n\n",
    before: "Rails.application.routes.draw do"

  content = <<-RUBY
    authenticate :account, lambda { |u| u.admin? } do
      mount Sidekiq::Web => '/sidekiq'
    end
  RUBY
  insert_into_file "config/routes.rb", "#{content}\n\n", after: "Rails.application.routes.draw do\n"
end

def add_administrate
  generate "administrate:install"

  gsub_file "app/dashboards/account_dashboard.rb",
    /email: Field::String/,
    "email: Field::String,\n    password: Field::String.with_options(searchable: false)"

  gsub_file "app/dashboards/account_dashboard.rb",
    /FORM_ATTRIBUTES = \[/,
    "FORM_ATTRIBUTES = [\n    :password,"

  gsub_file "app/dashboards/account_dashboard.rb",
    /:encrypted_password,/,
    ""

  gsub_file "app/controllers/admin/application_controller.rb",
    /# TODO Add authentication logic here\./,
    "redirect_to '/', alert: 'Not authorized.' unless account_signed_in? && current_account.admin?"

  environment do <<-RUBY
    # Expose our application's helpers to Administrate
    config.to_prepare do
      Administrate::ApplicationController.helper #{@app_name.camelize}::Application.helpers
    end
  RUBY
  end
end

def add_whenever
  run "wheneverize ."
end

def add_friendly_id
  generate "friendly_id"

  insert_into_file(
    Dir["db/migrate/**/*friendly_id_slugs.rb"].first,
    "[5.2]",
    after: "ActiveRecord::Migration"
  )
end

def stop_spring
  run "spring stop"
end

# Main setup
add_template_repository_to_source_path

add_gems

after_bundle do
  set_application_name
  stop_spring
  add_accounts
  add_javascript
  add_sidekiq
  add_friendly_id
  copy_templates
  add_whenever

  # Migrate
  rails_command "db:create"
  rails_command "db:migrate"

  # Migrations must be done before this
  add_administrate

  # Commit everything to git
  git :init
  git add: "."
  git commit: %Q{ -m 'Initial commit' }

  say
  say "Template app #{app_name} successfully created!", :blue
  say
  say "To get started with your new app:", :green
  say "cd #{app_name} - Switch to your new app's directory."
  say "foreman start - Run Rails, sidekiq, and webpack-dev-server."
end
