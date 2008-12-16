module Hyrarchy
  module AwesomeNestedSetCompatibility
    module ClassMethods
      # Returns the first root node.
      def root
        roots.first
      end

      # Returns true if the model's left and right values are valid, and all
      # root nodes have no ancestors.
      def valid?
        left_and_rights_valid? && all_roots_valid?
      end

      # Returns true if the model's left and right values match the parent_id
      # attributes.
      def left_and_rights_valid?
        # Load all nodes and index them by ID so we can leave the database
        # alone.
        nodes = connection.select_all("SELECT id, lft_numer, lft_denom, parent_id FROM #{quoted_table_name}")
        nodes_by_id = {}
        nodes.each do |node|
          node['id']           = node['id'].to_i
          node['encoded_path'] = Hyrarchy::EncodedPath(node['lft_numer'].to_i, node['lft_denom'].to_i)
          node['parent_id']    = node['parent_id'] ? node['parent_id'].to_i : nil
          nodes_by_id[node['id']] = node
        end
        # Check to see if the structure defined by the nodes' encoded paths
        # matches the structure defined by their parent_id attributes.
        nodes.all? do |node|
          if node['parent_id'].nil?
            node['encoded_path'].parent == nil rescue false
          else
            parent = nodes_by_id[node['parent_id']]
            parent && node['encoded_path'].parent == parent['encoded_path']
          end
        end
      end

      # Always returns true. This method exists solely for compatibility with
      # awesome_nested_set; the test it performs doesn't apply to Hyrarchy.
      def no_duplicates_for_columns?
        true
      end

      # Returns true if all roots have no ancestors.
      def all_roots_valid?
        each_root_valid?(roots)
      end

      # Returns true if all of the nodes in +roots_to_validate+ have no
      # ancestors.
      def each_root_valid?(roots_to_validate)
        roots_to_validate.all? {|r| r.root?}
      end

      # Rebuilds the model's hierarchy attributes based on the parent_id
      # attributes.
      def rebuild!
        return true if valid?
        
        update_all("lft = id, rgt = id, lft_numer = id, lft_denom = id")
        reset_all_free_child_paths
        
        paths_by_id = {}
        
        nodes = roots
        until nodes.empty? do
          nodes.each do |node|
            parent_path = paths_by_id[node.parent_id] || Hyrarchy::EncodedPath::ROOT
            node.send(:encoded_path=, next_child_encoded_path(parent_path))
            node.send(:create_or_update_without_callbacks) || raise(RecordNotSaved)
            paths_by_id[node.id] = node.send(:encoded_path)
          end
          node_ids = nodes.collect {|n| n.id}
          nodes = find(:all, :conditions => { :parent_id => node_ids })
        end
      end
    end
    
    module InstanceMethods
      # Returns this node's left value. Records that haven't yet been saved
      # won't have left values.
      def left
        encoded_path
      end

      # Returns this node's left value. Records that haven't yet been saved
      # won't have right values.
      def right
        encoded_path && encoded_path.next_farey_fraction
      end

      # Returns true if this is a root node.
      def root?
        (encoded_path.nil? || depth == 0 || @make_root) && !@new_parent
      end

      # Returns true if this node has no children.
      def leaf?
        children.empty?
      end

      # Returns true if this node is a child of another node.
      def child?
        !root?
      end

      # Compares two nodes by their left values.
      def <=>(x)
        x.left <=> left
      end

      # Returns an array containing this node and its ancestors, starting with
      # this node and ending with its root. The array returned by this method
      # is a has_many association, so you can do things like this:
      #
      #   node.self_and_ancestors.find(:all, :conditions => { ... })
      #
      def self_and_ancestors
        ancestors(true)
      end

      # Returns an array containing this node and its siblings. The array
      # returned by this method is a has_many association, so you can do things
      # like this:
      #
      #   node.self_and_siblings.find(:all, :conditions => { ... })
      #
      def self_and_siblings
        siblings(true)
      end

      # Returns an array containing this node's siblings. The array returned by
      # this method is a has_many association, so you can do things like this:
      #
      #   node.siblings.find(:all, :conditions => { ... })
      #
      def siblings(with_self = false)
        cache_key = with_self ? :self_and_siblings : :siblings
        return cached[cache_key] if cached[cache_key]

        if with_self
          conditions = { :parent_id => parent_id }
        else
          conditions = ["parent_id #{parent_id.nil? ? 'IS' : '='} ? AND id <> ?",
            parent_id, id]
        end

        cached[cache_key] = self.class.scoped(
          :conditions => conditions,
          :order      => 'lft DESC'
        )
      end

      # Returns an array containing this node's childless descendants. The
      # array returned by this method is a named scope.
      def leaves
        cached[:leaves] ||= descendants.scoped :conditions => "NOT EXISTS (
          SELECT * FROM #{self.class.quoted_table_name} tt
          WHERE tt.parent_id = #{self.class.quoted_table_name}.id
        )"
      end

      # Alias for depth.
      def level
        depth
      end

      # Returns an array of this node and its descendants: its children,
      # grandchildren, and so on. The array returned by this method is a
      # has_many association, so you can do things like this:
      #
      #   node.self_and_descendants.find(:all, :conditions => { ... })
      #
      def self_and_descendants
        cached[:self_and_descendants] ||= CollectionProxy.new(
          self,
          :descendants,
          :conditions => { :lft => (lft - FLOAT_FUDGE_FACTOR)..(rgt + FLOAT_FUDGE_FACTOR) },
          :order => 'lft DESC',
          # The query conditions intentionally load extra records that aren't
          # descendants to account for floating point imprecision. This
          # procedure removes the extra records.
          :after => Proc.new do |records|
            r = encoded_path.next_farey_fraction
            records.delete_if do |n|
              n.encoded_path < encoded_path || n.encoded_path >= r
            end
          end,
          # The regular count method doesn't work because of the fudge factor
          # in the conditions. This procedure uses the length of the records
          # array if it's been loaded. Otherwise it does a raw SQL query (to
          # avoid the expense of instantiating a bunch of ActiveRecord objects)
          # and prunes the results in the same manner as the :after procedure.
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
                p < encoded_path || p >= r
              end
              rows.length
            end
          end
        )
      end

      # Returns true if this node is a descendant of +other+.
      def is_descendant_of?(other)
        left > other.left && left <= other.right
      end

      # Returns true if this node is a descendant of +other+, or if this node
      # is +other+.    
      def is_or_is_descendant_of?(other)
        left >= other.left && left <= other.right
      end

      # Returns true if this node is an ancestor of +other+.
      def is_ancestor_of?(other)
        other.left > left && other.left <= right
      end

      # Returns true if this node is an ancestor of +other+, or if this node is
      # +other+.
      def is_or_is_ancestor_of?(other)
        other.left >= left && other.left <= right
      end

      # Always returns true. This method exists solely for compatibility with
      # awesome_nested_set; Hyrarchy doesn't support scoping (but maybe it will
      # some day).
      def same_scope?(other)
        true
      end

      def left_sibling # :nodoc:
        raise NotImplementedError, "awesome_nested_set's left_sibling method isn't implemented in this version of Hyrarchy"
      end

      def right_sibling # :nodoc:
        raise NotImplementedError, "awesome_nested_set's right_sibling method isn't implemented in this version of Hyrarchy"
      end

      def move_left # :nodoc:
        raise NotImplementedError, "awesome_nested_set's move_left method isn't implemented in this version of Hyrarchy"
      end

      def move_right # :nodoc:
        raise NotImplementedError, "awesome_nested_set's move_right method isn't implemented in this version of Hyrarchy"
      end

      def move_to_left_of(other) # :nodoc:
        raise NotImplementedError, "awesome_nested_set's move_to_left_of method isn't implemented in this version of Hyrarchy"
      end

      def move_to_right_of(other) # :nodoc:
        raise NotImplementedError, "awesome_nested_set's move_to_right_of method isn't implemented in this version of Hyrarchy"
      end

      # Sets this node's parent to +node+ and calls save!.
      def move_to_child_of(node)
        node = self.class.find(node)
        self.parent = node
        save!
      end

      # Makes this node a root node and calls save!.
      def move_to_root
        self.parent = nil
        save!
      end

      def move_possible?(target) # :nodoc:
        raise NotImplementedError, "awesome_nested_set's move_possible? method isn't implemented in this version of Hyrarchy"
      end

      # Returns a textual representation of this node and its descendants.
      def to_text
        self_and_descendants.map do |node|
          "#{'*'*(node.depth+1)} #{node.id} #{node.to_s} (#{node.parent_id}, #{node.left}, #{node.right})"
        end.join("\n")
      end
    end
  end
end
