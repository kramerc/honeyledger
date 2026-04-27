unless Rails.application.config.eager_load
  Rails.application.config.to_prepare do
    Simplefin::Account
    Lunchflow::Account
  end
end
