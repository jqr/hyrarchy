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
        return true if (valid? rescue false)
        
        update_all("lft = id, rgt = id, lft_numer = id, lft_denom = id")
        paths_by_id = {}
        order_by = columns_hash['created_at'] ? :created_at : :id
        
        nodes = roots :order => order_by
        until nodes.empty? do
          nodes.each do |node|
            parent_path = paths_by_id[node.parent_id] || Hyrarchy::EncodedPath::ROOT
            node.send(:encoded_path=, next_child_encoded_path(parent_path))
            node.send(:create_or_update_without_callbacks) || raise(RecordNotSaved)
            paths_by_id[node.id] = node.send(:encoded_path)
          end
          node_ids = nodes.collect {|n| n.id}
          nodes = find(:all, :conditions => { :parent_id => node_ids }, :order => order_by)
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
          :order      => 'rgt DESC, lft'
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
          :order => 'rgt DESC, lft',
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
          end,
          # Associations don't normally have an optimized index method, but
          # this one does. :)
          :index => Proc.new do |obj|
            rows = self.class.connection.select_all("
              SELECT id, lft_numer, lft_denom
              FROM #{self.class.quoted_table_name}
              WHERE #{descendants.conditions}
              ORDER BY rgt DESC, lft")
            r = encoded_path.next_farey_fraction
            rows.delete_if do |row|
              p = Hyrarchy::EncodedPath(
                row['lft_numer'].to_i,
                row['lft_denom'].to_i)
              row.delete('lft_numer')
              row.delete('lft_denom')
              p < encoded_path || p >= r
            end
            rows.index({'id' => obj.id.to_s})
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

      # Returns the sibling after this node. If this node is its parent's last
      # child, returns nil.
      def right_sibling
        return nil if self == parent.children.last
        sibling_path = send(:encoded_path).next_sibling
        until self.class.exists?(:lft_numer => sibling_path.numerator, :lft_denom => sibling_path.denominator)
          sibling_path = sibling_path.next_sibling
        end
        self.class.send(:find_by_encoded_path, sibling_path)
      end

      def move_left # :nodoc:
        raise NotImplementedError, "awesome_nested_set's move_left method isn't implemented in this version of Hyrarchy"
      end

      def move_right # :nodoc:
        raise NotImplementedError, "awesome_nested_set's move_right method isn't implemented in this version of Hyrarchy"
      end
      
      # The semantics of left and right don't quite map exactly from
      # awesome_nested_set to Hyrarchy. For the purpose of this method, "left"
      # means "before."
      #
      # If this node isn't a sibling of +other+, its parent will be set to
      # +other+'s parent.
      def move_to_left_of(other) # :nodoc:
        # Don't attempt an impossible move.
        if other.is_descendant_of?(self)
          raise ArgumentError, "you can't move a node to the left of one of its descendants"
        end
        # Find the first unused path after +other+'s path.
        open_path = other.send(:encoded_path).next_sibling
        while self.class.exists?(:lft_numer => open_path.numerator, :lft_denom => open_path.denominator)
          open_path = open_path.next_sibling
        end
        # Move +other+, and all nodes following it, down.
        while open_path != other.send(:encoded_path)
          p = open_path.previous_sibling
          n = self.class.send(:find_by_encoded_path, p)
          n.send(:encoded_path=, open_path)
          n.save!
          open_path = p
        end
        puts open_path
        # Insert this node.
        send(:encoded_path=, open_path)
        save!
      end

      # The semantics of left and right don't quite map exactly from
      # awesome_nested_set to Hyrarchy. For the purpose of this method, "right"
      # means "after."
      #
      # If this node isn't a sibling of +other+, its parent will be set to
      # +other+'s parent.
      def move_to_right_of(other)
        # Don't attempt an impossible move.
        if other.is_descendant_of?(self)
          raise ArgumentError, "you can't move a node to the right of one of its descendants"
        end
        # If +other+ is its parent's last child, we can simply append this node
        # to the parent's children.
        if other == other.parent.children.last
          send(:encoded_path=, other.parent.send(:next_child_encoded_path))
          save!
        else
          # Otherwise, this is equivalent to moving this node to the left of
          # +other+'s right sibling.
          move_to_left_of(other.right_sibling)
        end
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
