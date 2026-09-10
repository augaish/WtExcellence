class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Every record leaves a trace of who created, changed or deleted it.
  include ActivityTrail
end
