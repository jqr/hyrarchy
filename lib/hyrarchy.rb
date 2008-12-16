require 'hyrarchy/encoded_path'
require 'hyrarchy/collection_proxy'

module Hyrarchy
  # Fudge factor to account for imprecision with floating point approximations
  # of a node's left and right fractions.
  FLOAT_FUDGE_FACTOR = 0.0000000000001 # :nodoc:
  
  # Mixes Hyrarchy into ActiveRecord.
  def self.activate!
    ActiveRecord::Base.extend IsHierarchic
    ActiveRecord::Migration.extend Migrations
  end
  
  # These methods are available in ActiveRecord migrations for adding and
  # removing columns and indexes required by Hyrarchy.
  module Migrations
    def add_hierarchy(table)
      add_column table, :lft,       :float
      add_column table, :rgt,       :float
      add_column table, :lft_numer, :integer
      add_column table, :lft_denom, :integer
      add_column table, :parent_id, :integer
      add_index table, :lft
      add_index table, [:lft_numer, :lft_denom], :unique => true
      add_index table, :parent_id
    end
    
    def remove_hierarchy(table)
      remove_column table, :lft
      remove_column table, :rgt
      remove_column table, :lft_numer
      remove_column table, :lft_denom
      remove_column table, :parent_id, :integer
      remove_index table, :lft
      remove_index table, [:lft_numer, :lft_denom]
      remove_index table, :parent_id
    end
  end
  
  module IsHierarchic
    # Declares that a model represents hierarchic data. Adds a has_many
    # association for instances' children, and a named scope for the model's
    # root nodes (called +roots+).
    def is_hierarchic
      extend ClassMethods
      include InstanceMethods
      
      has_many :children,
        :foreign_key => 'parent_id',
        :order       => 'lft DESC',
        :class_name  => self.to_s,
        :dependent   => :destroy
      
      before_save :set_encoded_paths
      before_save :set_parent_id
      after_destroy :mark_path_free
      
      named_scope :roots,
        :conditions => { :parent_id => nil },
        :order      => 'lft DESC'
    end
  end
  
  # These private methods are available to model classes that have been
  # declared is_hierarchic. They're used internally and aren't intended to be
  # used by application developers.
  module ClassMethods # :nodoc:
  private
    
    # Returns an array of unused child paths beneath +parent_path+.
    def free_child_paths(parent_path)
      @@free_child_paths ||= {}
      @@free_child_paths[parent_path] ||= []
    end
    
    # Stores +path+ in the arrays of free child paths.
    def child_path_is_free(path)
      parent_path = path.parent(false)
      free_child_paths(parent_path) << path
      free_child_paths(parent_path).sort!
    end
    
    # Removes all paths from the array of free child paths for +parent_path+.
    def reset_free_child_paths(parent_path)
      free_child_paths(parent_path).clear
    end
    
    # Finds the first unused child path beneath +parent_path+.
    def next_child_encoded_path(parent_path)
      p = free_child_paths(parent_path).shift || parent_path.first_child
      while true do
        if exists?(:lft_numer => p.numerator, :lft_denom => p.denominator)
          p = parent_path.mediant(p)
        else
          if free_child_paths(parent_path).empty?
            child_path_is_free(parent_path.mediant(p))
          end
          return p
        end
      end
    end
    
    # Returns the node with the specified encoded path.
    def find_by_encoded_path(p)
      find(:first, :conditions => {
        :lft_numer => p.numerator,
        :lft_denom => p.denominator
      })
    end
  end
  
  # These methods are available to instances of models that have been declared
  # is_hierarchic.
  module InstanceMethods
    # Returns this node's parent, or +nil+ if this is a root node.
    def parent
      return @new_parent if @new_parent
      p = encoded_path.parent
      return nil if p.nil?
      self.class.send(:find_by_encoded_path, p)
    end
    
    # Sets this node's parent. To make this node a root node, set its parent to
    # +nil+.
    def parent=(other)
      @make_root = false
      if other.nil?
        @new_parent = nil
        @make_root = true
      elsif encoded_path && other.encoded_path == encoded_path.parent
        @new_parent = nil
      else
        @new_parent = other
      end
      other
    end
    
    # Returns an array of this node's descendants: its children, grandchildren,
    # and so on. The array returned by this method is a has_many association,
    # so you can do things like this:
    #
    #   node.descendants.find(:all, :conditions => { ... })
    #
    def descendants
      @descendants ||= CollectionProxy.new(
        self,
        :descendants,
        :conditions => { :lft => (lft - FLOAT_FUDGE_FACTOR)..(rgt + FLOAT_FUDGE_FACTOR) },
        :order => 'lft DESC',
        # The query conditions intentionally load extra records that aren't
        # descendants to account for floating point imprecision. This procedure
        # removes the extra records.
        :after => Proc.new do |records|
          r = encoded_path.next_farey_fraction
          records.delete_if do |n|
            n.encoded_path <= encoded_path || n.encoded_path >= r
          end
        end,
        # The regular count method doesn't work because of the fudge factor in
        # the conditions. This procedure uses the length of the records array
        # if it's been loaded. Otherwise it does a raw SQL query (to avoid the
        # expense of instantiating a bunch of ActiveRecord objects) and prunes
        # the results in the same manner as the :after procedure.
        :count => Proc.new do
          if descendants.loaded?
            descendants.length
          else
            rows = self.class.connection.select_all("
              SELECT lft_numer, lft_denom
              FROM #{self.class.quoted_table_name}
              WHERE #{descendants.conditions}")
            r = encoded_path.next_farey_fraction
            rows.delete_if do |row|
              p = Hyrarchy::EncodedPath(
                row['lft_numer'].to_i,
                row['lft_denom'].to_i)
              p <= encoded_path || p >= r
            end
            rows.length
          end
        end
      )
    end
    
    # Returns an array of this node's ancestors--its parent, grandparent, and
    # so on--ordered from parent to root. The array returned by this method is
    # a has_many association, so you can do things like this:
    #
    #   node.ancestors.find(:all, :conditions => { ... })
    #
    def ancestors
      return @ancestors if @ancestors
      
      paths = []
      path = encoded_path.parent
      while path do
        paths << path
        path = path.parent
      end
      
      @ancestors ||= CollectionProxy.new(
        self,
        :ancestors,
        :conditions => paths.empty? ? "id <> id" : [
          paths.collect {|p| "(lft_numer = ? AND lft_denom = ?)"}.join(" OR "),
          *(paths.collect {|p| [p.numerator, p.denominator]}.flatten)
        ],
        :order => 'lft DESC'
      )
    end
    
    # Returns the root node related to this node, or nil if this node is a root
    # node.
    def root
      return @root if @root
      
      path = encoded_path.parent
      while path do
        parent = path.parent
        break if parent.nil?
        path = parent
      end
      
      if path
        self.class.send :find_by_encoded_path, path
      else
        nil
      end
    end
    
    # Returns the number of nodes between this one and the top of the tree.
    def depth
      encoded_path.depth - 1
    end
    
    def reload(options = nil)
      @root = @ancestors = @descendants = @descendants_count = nil
      super
    end

  protected
    
    # Sets the node's encoded path, updating all relevant database columns to
    # match.
    def encoded_path=(r) # :nodoc:
      @root = @ancestors = @descendants = @descendants_count = nil
      if r.nil?
        self.lft_numer = nil
        self.lft_denom = nil
        self.lft = nil
        self.rgt = nil
      else
        self.lft_numer = r.numerator
        self.lft_denom = r.denominator
        self.lft = r.to_f
        self.rgt = encoded_path.next_farey_fraction.to_f
      end
      r
    end
    
    # Returns the node's encoded path (its rational left value).
    def encoded_path # :nodoc:
      return nil if lft_numer.nil? || lft_denom.nil?
      Hyrarchy::EncodedPath(lft_numer, lft_denom)
    end
    
  private
    
    # before_save callback to ensure that this node's encoded path is a child
    # of its parent, and that its descendants' paths are updated if this node
    # has moved.
    def set_encoded_paths # :nodoc:
      p = nil
      self.lft_numer = self.lft_denom = nil if @make_root
      
      if @new_parent.nil?
        if lft_numer.nil? || lft_denom.nil?
          p = Hyrarchy::EncodedPath::ROOT
        end
      else
        p = @new_parent.encoded_path
      end
      
      if p
        new_path = self.class.send(:next_child_encoded_path, p)
        if encoded_path != new_path
          self.class.send(:reset_free_child_paths, encoded_path)
          self.encoded_path = self.class.send(:next_child_encoded_path, p)
          children.each do |c|
            c.parent = self
            c.save!
          end
        end
      end
      
      true
    end
    
    # before_save callback to ensure that this node's parent_id attribute
    # agrees with its encoded path.
    def set_parent_id # :nodoc:
      parent = self.class.send(:find_by_encoded_path, encoded_path.parent(false))
      self.parent_id = parent ? parent.id : nil
      true
    end
    
    # after_destroy callback to add this node's encoded path to its parent's
    # list of available child paths.
    def mark_path_free # :nodoc:
      self.class.send(:child_path_is_free, encoded_path)
    end
  end
end
