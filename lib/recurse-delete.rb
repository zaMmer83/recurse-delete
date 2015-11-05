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
    parent_class.reflect_on_all_associations.select do |assoc|
      [:destroy, :destroy_all, :delete, :delete_all].include? assoc.options[:dependent]
    end.each do |assoc|
      if belongs_to_polymorphic_association?(assoc)
        parent_class.where(:id => parent_ids).pluck(assoc.foreign_type, assoc.foreign_key).group_by do |tuple|
          tuple.first
        end.each do |dependent_class_name, dependent_ids|
          dependent_class = dependent_class_name.constantize rescue nil
          delete_recursively(dependent_class, dependent_ids.map(&:second)) if dependent_class
        end
      else
        dependent_class = assoc.klass
        condition = {}
        if polymorphic_association?(assoc)
          dependent_assoc = dependent_class.reflections[assoc.options[:as]]
          if dependent_assoc
            dependent_key = assoc.macro == :belongs_to ? dependent_class.primary_key : dependent_assoc.foreign_key
            condition[dependent_key] = parent_ids
            condition[dependent_assoc.foreign_type] = parent_class.to_s
          end
        else
          key = assoc.macro == :belongs_to ? dependent_class.primary_key : assoc.foreign_key
          condition[key] = parent_ids
        end
        unless condition.empty?
          dependent_ids = dependent_class.where(condition).pluck(:id)
          delete_recursively(dependent_class, dependent_ids)
        end
      end
    end

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
