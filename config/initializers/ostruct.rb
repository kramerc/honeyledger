# OpenStruct is no longer autoloaded as of Ruby 3.5 / Rails 8.1, but it's used
# from at least one view (app/views/csv/imports/show.html.erb) to wrap the
# stored column_mappings hash for fields_for. Require it at boot so views and
# controllers don't need to reach for a bare `require "ostruct"` themselves.
require "ostruct"
