namespace :tmp do
  namespace :"screenshots_js" do
    desc "Clear tmp/screenshots-js directory"
    task :clear do
      FileUtils.rm_rf(Rails.root.join("tmp/screenshots-js"))
    end
  end
end

task "tmp:clear" => [ "tmp:screenshots_js:clear" ]
