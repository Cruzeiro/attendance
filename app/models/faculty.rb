class Faculty < ActiveRecord::Base
  attr_accessible :abbr, :title

  has_many :groups
end
