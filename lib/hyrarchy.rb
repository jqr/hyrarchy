require 'hyrarchy/encoded_path'

module Hyrarchy
  FLOAT_FUDGE_FACTOR = 0.0000000000001
  
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
    
    def free_child_paths(parent_path)
      @@free_child_paths ||= {}
      @@free_child_paths[parent_path] ||= []
    end
    
    def child_path_is_free(path)
      parent_path = path.parent(false)
      free_child_paths(parent_path) << path
      free_child_paths(parent_path).sort!
    end
    
    def reset_free_child_paths(parent_path)
      free_child_paths(parent_path).clear
    end
    
    def next_child_encoded_path(parent_path)
      p = free_child_paths(parent_path).shift || parent_path.first_child
      while true do
        cnt = connection.select_all("
          SELECT count(1) cnt
          FROM #{quoted_table_name}
          WHERE lft_numer = #{p.numerator} AND lft_denom = #{p.denominator}
        ").first['cnt'].to_i
        if cnt == 1
          p = parent_path.mediant(p)
        else
          if free_child_paths(parent_path).empty?
            child_path_is_free(parent_path.mediant(p))
          end
          return p
        end
      end
    end
    
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
      if encoded_path && other.encoded_path == encoded_path.parent
        @new_parent = nil
      else
        @new_parent = other
      end
      other
    end
    
    # Returns this node's descendants: its children, grandchildren, and so on.
    def descendants
      nodes = self.class.find(
        :all,
        :conditions => { :lft => (lft - FLOAT_FUDGE_FACTOR)..(rgt + FLOAT_FUDGE_FACTOR) },
        :order      => 'lft DESC'
      )
      r = encoded_path.next_farey_fraction
      nodes.delete_if do |n|
        n.encoded_path <= encoded_path || n.encoded_path >= r
      end
      nodes
    end
    
    # Returns this node's ancestors: its parent, grandparent, and so on.
    def ancestors
      nodes = []
      node = self
      while true do
        node = node.parent
        return nodes if node.nil?
        nodes << node
      end
    end
    
    # Returns the root node related to this node, or nil if this node is a root
    # node.
    def root
      ancestors.last
    end
    
    # Returns the number of nodes between this one and the top of the tree.
    def depth
      encoded_path.depth - 1
    end

  protected
    
    # Sets the node's encoded path, updating all relevant database columns to
    # match.
    def encoded_path=(r)
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
    def encoded_path
      return nil if lft_numer.nil? || lft_denom.nil?
      Hyrarchy::EncodedPath(lft_numer, lft_denom)
    end
    
  private
    
    # before_save callback to ensure that this node's encoded path as a child
    # of its parent, and that its descendants' paths are updated if this node
    # has moved.
    def set_encoded_paths
      p = nil
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
    def set_parent_id
      parent = self.class.send(:find_by_encoded_path, encoded_path.parent(false))
      self.parent_id = parent ? parent.id : nil
      true
    end
    
    # after_destroy callback to add this node's encoded path to its parent's
    # list of available child paths.
    def mark_path_free
      self.class.send(:child_path_is_free, encoded_path)
    end
  end
end
