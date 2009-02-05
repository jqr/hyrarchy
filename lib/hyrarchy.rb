require 'hyrarchy/encoded_path'
require 'hyrarchy/collection_proxy'
require 'hyrarchy/awesome_nested_set_compatibility'

module Hyrarchy
  # Fudge factor to account for imprecision with floating point approximations
  # of a node's left and right fractions.
  FLOAT_FUDGE_FACTOR = 0.00000000001 # :nodoc:
  
  # Mixes Hyrarchy into ActiveRecord.
  def self.activate!
    ActiveRecord::Base.extend IsHierarchic
    ActiveRecord::Migration.extend Migrations
  end
  
  # These methods are available in ActiveRecord migrations for adding and
  # removing columns and indexes required by Hyrarchy.
  module Migrations
    def add_hierarchy(table, options = {})
      convert = options.delete(:convert)
      unless options.empty?
        raise(ArgumentError, "unknown keys: #{options.keys.join(', ')}")
      end
      
      case convert
      when :awesome_nested_set
        remove_column table, :lft
        remove_column table, :rgt
      when '', nil
      else
        raise(ArgumentError, "don't know how to convert hierarchy from #{convert}")
      end
      
      add_column table, :lft,       :float
      add_column table, :rgt,       :float
      add_column table, :lft_numer, :integer
      add_column table, :lft_denom, :integer
      add_column table, :parent_id, :integer unless convert == :awesome_nested_set
      add_index table, :lft
      add_index table, [:lft_numer, :lft_denom], :unique => true
      add_index table, :parent_id
    end
    
    def remove_hierarchy(table, options = {})
      convert = options.delete(:convert)
      unless options.empty?
        raise(ArgumentError, "unknown keys: #{options.keys.join(', ')}")
      end
      
      remove_column table, :lft
      remove_column table, :rgt
      remove_column table, :lft_numer
      remove_column table, :lft_denom
      remove_column table, :parent_id, :integer unless convert == :awesome_nested_set
      
      case convert
      when :awesome_nested_set
        add_column table, :lft, :integer
        add_column table, :rgt, :integer
      when '', nil
      else
        raise(ArgumentError, "don't know how to convert hierarchy to #{convert}")
      end
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
        :order       => 'rgt DESC, lft',
        :class_name  => self.to_s,
        :dependent   => :destroy
      
      before_save :set_encoded_paths
      before_save :set_parent_id
      after_save :update_descendant_paths
      after_save :reset_flags
      
      named_scope :roots,
        :conditions => { :parent_id => nil },
        :order      => 'rgt DESC, lft'
    end
  end
  
  # These private methods are available to model classes that have been
  # declared is_hierarchic. They're used internally and aren't intended to be
  # used by application developers.
  module ClassMethods # :nodoc:
    include Hyrarchy::AwesomeNestedSetCompatibility::ClassMethods
    
  private
    
    # Finds the first unused child path beneath +parent_path+.
    def next_child_encoded_path(parent_path)
      if parent_path == Hyrarchy::EncodedPath::ROOT
        if sibling = roots.last
          child_path = sibling.send(:encoded_path).next_sibling
        else
          child_path = Hyrarchy::EncodedPath::ROOT.first_child
        end
      else
        node = find_by_encoded_path(parent_path)
        child_path = node ?
          node.send(:next_child_encoded_path) : parent_path.first_child
      end
      while self.exists?(:lft_numer => p.numerator, :lft_denom => p.denominator)
        child_path = p.next_sibling
      end
      child_path
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
    include Hyrarchy::AwesomeNestedSetCompatibility::InstanceMethods
    
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
      elsif encoded_path && other.encoded_path == (encoded_path.parent rescue nil)
        @new_parent = nil
      else
        @new_parent = other
      end
      other
    end
    
    # Returns an array of this node's descendants: its children, grandchildren,
    # and so on. The array returned by this method is a named scope.
    def descendants
      cached[:descendants] ||=
        self_and_descendants.scoped :conditions => "id <> #{id}"
    end
    
    # Returns an array of this node's ancestors--its parent, grandparent, and
    # so on--ordered from parent to root. The array returned by this method is
    # a has_many association, so you can do things like this:
    #
    #   node.ancestors.find(:all, :conditions => { ... })
    #
    def ancestors(with_self = false)
      cache_key = with_self ? :self_and_ancestors : :ancestors
      return cached[cache_key] if cached[cache_key]
      
      paths = []
      path = with_self ? encoded_path : encoded_path.parent
      while path do
        paths << path
        path = path.parent
      end
      
      cached[cache_key] = CollectionProxy.new(
        self,
        cache_key,
        :conditions => paths.empty? ? "id <> id" : [
          paths.collect {|p| "(lft_numer = ? AND lft_denom = ?)"}.join(" OR "),
          *(paths.collect {|p| [p.numerator, p.denominator]}.flatten)
        ],
        :order => 'rgt, lft DESC'
      )
    end
    
    # Returns the root node related to this node, or nil if this node is a root
    # node.
    def root
      return cached[:root] if cached[:root]
      
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
    
    # Overrides ActiveRecord's reload method to clear cached scopes and ad hoc
    # associations.
    def reload(options = nil) # :nodoc:
      @cached = {}
      reset_flags
      super
    end

  protected
    
    # Sets the node's encoded path, updating all relevant database columns to
    # match.
    def encoded_path=(r) # :nodoc:
      @cached = {}
      if r.nil?
        self.lft_numer = nil
        self.lft_denom = nil
        self.lft = nil
        self.rgt = nil
      else
        @path_has_changed = true
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
    
    # Returns a hash for caching scopes and ad hoc associations.
    def cached # :nodoc:
      @cached ||= {}
    end
    
    # Returns the first unused child path under this node.
    def next_child_encoded_path
      return nil unless encoded_path
      if children.empty?
        encoded_path.first_child
      else
        children.last.send(:encoded_path).next_sibling
      end
    end
    
  private
    
    # before_save callback to ensure that this node's encoded path is a child
    # of its parent.
    def set_encoded_paths # :nodoc:
      @path_has_changed = false if @path_has_changed.nil?
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
        if @path_has_changed = (encoded_path != new_path)
          self.encoded_path = new_path
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
    
    # after_save callback to ensure that this node's descendants are updated if
    # this node has moved.
    def update_descendant_paths # :nodoc:
      return true unless @path_has_changed
      children.reload if children.loaded? && children.empty?
      
      child_path = encoded_path.first_child
      children.each do |c|
        c.encoded_path = child_path
        c.save!
        child_path = child_path.next_sibling
      end
      
      true
    end
    
    # Resets internal flags after saving.
    def reset_flags # :nodoc:
      @path_has_changed = @new_parent = @make_root = nil
    end
  end
end
