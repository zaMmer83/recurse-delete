# Recurse Delete by JD Isaacks (jisaacks.com)
#
# Copyright (c) 2012 John Isaacks
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module RecurseDelete
  extend ActiveSupport::Concern

  def recurse_delete
    ActiveRecord::Base.transaction do
      delete_recursively self.class, self.id
    end
  end

  def delete_recursively(parent_class, parent_ids)
    # get the assocs for the parent class
    parent_class.reflect_on_all_associations.select do |assoc|
      [:destroy, :destroy_all, :delete, :delete_all].include? assoc.options[:dependent]
    end.each do |assoc|
      if belongs_to_polymorphic_association?(assoc)
        foreign_key = assoc.options[:foreign_key] || "#{assoc.name}_id".to_sym
        foreign_type = assoc.options[:foreign_type] || "#{assoc.name}_type".to_sym
        parent_class.where(:id => parent_ids).pluck(foreign_type, foreign_key).group_by do |tuple|
          tuple.first
        end.each do |dependent_class_name, dependent_ids|
          delete_recursively(dependent_class_name.constantize, dependent_ids.map(&:second))
        end
      else
        # get the dependent class
        dependent_class = assoc.name.to_s.classify.constantize

        # get the foreign class; table_name is used to support STI
        foreign_class = parent_class.table_name.classify
        if polymorphic_association?(assoc)
          # get the foreign key
          foreign_key = assoc.options[:as].to_s.foreign_key
          # get the foreign type
          foreign_type = foreign_key.gsub('_id', '_type')
          # get all the dependent record ids
          dependent_ids = dependent_class.where(foreign_key => parent_ids, foreign_type => foreign_class).pluck(:id)
        else
          foreign_key = assoc.options[:foreign_key].present? ? assoc.options[:foreign_key] : foreign_class.foreign_key
          dependent_ids = dependent_class.where(foreign_key => parent_ids).pluck(:id)
        end
        # recurse
        delete_recursively(dependent_class, dependent_ids)
      end
    end
    # delete all the parent records
    parent_class.delete_all(:id => parent_ids)

  end

  def polymorphic_association?(assoc)
    assoc.options[:as].present?
  end

  def belongs_to_polymorphic_association?(assoc)
    assoc.macro == :belongs_to && assoc.options[:polymorphic]
  end

  module ClassMethods
    def recurse_delete_all
      delete_all
      assocs = reflect_on_all_associations.select do |assoc|
        [:destroy, :destroy_all, :delete, :delete_all].include? assoc.options[:dependent]
      end
      assocs.each do |assoc|
        assoc.klass.recurse_delete_all
      end
    end
  end

end

class ActiveRecord::Base
  include RecurseDelete
end
