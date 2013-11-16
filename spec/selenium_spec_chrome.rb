require 'spec_helper'

Capybara.register_driver :selenium_chrome do |app|
  Capybara::Selenium::Driver.new(app, :browser => :chrome, :args => ['no-sandbox'])
end

class ChromeTestApp < TestApp
  # Object.id is different from the TestApp used in firefox session so 
  # a new Capybar::Server instance will get launched for chrome testing
end

module TestSessions
  Chrome = Capybara::Session.new(:selenium_chrome, ChromeTestApp)
end

Capybara::SpecHelper.run_specs TestSessions::Chrome, "selenium_chrome", :skip => [
  :response_headers,
  :status_code,
  :trigger  
]
