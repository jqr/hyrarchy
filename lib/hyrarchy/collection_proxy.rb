module Hyrarchy
  # This is a shameful hack to create has_many associations with no foreign key
  # and an option for running a post-processing procedure on the array of
  # records. Hyrarchy uses this class to provide the features of a has_many
  # association on a node's ancestors and descendants arrays.
  class CollectionProxy < ActiveRecord::Associations::HasManyAssociation # :nodoc:
    def initialize(owner, name, options = {})
      @after = options.delete(:after)
      @count = options.delete(:count)
      @index = options.delete(:index)
      reflection = ActiveRecord::Base.create_reflection(
        :has_many, name, options.merge(:class_name => owner.class.to_s), owner.class)
      super(owner, reflection)
    end
    
    # This is ripped right from the construct_sql method in HasManyAssociation,
    # but the foreign key condition has been removed.
    def construct_sql
      if @reflection.options[:finder_sql]
        @finder_sql = interpolate_sql(@reflection.options[:finder_sql])
      else
        @finder_sql = conditions
      end
      
      if @reflection.options[:counter_sql]
        @counter_sql = interpolate_sql(@reflection.options[:counter_sql])
      elsif @reflection.options[:finder_sql]
        # replace the SELECT clause with COUNT(*), preserving any hints within /* ... */
        @reflection.options[:counter_sql] = @reflection.options[:finder_sql].sub(/SELECT (\/\*.*?\*\/ )?(.*)\bFROM\b/im) { "SELECT #{$1}COUNT(*) FROM" }
        @counter_sql = interpolate_sql(@reflection.options[:counter_sql])
      else
        @counter_sql = @finder_sql
      end
    end
    
    # Overrides find to run the association's +after+ procedure on the results.
    def find(*args)
      records = super
      @after.call(records) if @after
      records
    end
    
    # Overrides count to run the association's +count+ procedure, with caching.
    def count
      if @count
        if @count.respond_to?(:call)
          @count = @count.call
        else
          @count
        end
      else
        super
      end
    end
    
    # Overrides index to run the association's +index+ procedure.
    def index(obj)
      if @index && !loaded?
        @index.call(obj)
      else
        super
      end
    end
    
  protected
    
    # Overrides find_target to run the association's +after+ procedure on the
    # results.
    def find_target
      records = super
      @after.call(records) if @after
      records
    end
  end
end
