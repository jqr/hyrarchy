require 'rational'

module Hyrarchy
  # Returns a new path with numerator +n+ and denominator +d+, which will be
  # reduced if possible. Paths must be in the interval [0,1]. This method
  # correlates to the Rational(n, d) method.
  def self.EncodedPath(n, d) # :nodoc:
    r = EncodedPath.reduce n, d
    raise(RangeError, "paths must be in the interval [0,1]") if r < 0 || r > 1
    r
  end
  
  # An encoded path is a rational number that represents a node's position in
  # the tree. By using rational numbers instead of integers, new nodes can be
  # inserted arbitrarily without having to adjust the left and right values of
  # any other nodes. Farey sequences are used to prevent denominators from
  # growing exponentially and quickly exhausting the database's integer range.
  # For more information, see "Nested Intervals with Farey Fractions" by Vadim
  # Tropashko: http://arxiv.org/html/cs.DB/0401014
  class EncodedPath < Rational # :nodoc:
    # Path of the uppermost node in the tree. The node at this path has no
    # siblings, and all nodes descend from it.
    ROOT = Hyrarchy::EncodedPath(0, 1)
    
    # Returns the path of the parent of the node at this path. If +root_is_nil+
    # is true (the default) and the parent is the root node, returns nil.
    def parent(root_is_nil = true)
      r = next_farey_fraction
      p = Hyrarchy::EncodedPath(
        numerator - r.numerator,
        denominator - r.denominator)
      (root_is_nil && p == ROOT) ? nil : p
    end
    
    # Returns the depth of the node at this path, starting from the root node.
    # Paths in the uppermost layer (considered "root nodes" by the ActiveRecord
    # methods) have a depth of one.
    def depth
      n = self
      depth = 0
      while n != ROOT
        n = n.parent(false)
        depth += 1
      end
      depth
    end
    
    # Returns the path of the first child of the node at this path.
    def first_child
      mediant(next_farey_fraction)
    end
    
    # Returns the path of the sibling immediately after the node at this path.
    def next_sibling
      parent(false).mediant(self)
    end
    
    # Returns the path of the sibling immediately before the node at this path.
    # If this is the path of the first sibling, returns nil.
    def previous_sibling
      p = parent(false)
      return nil if self == p.first_child
      Hyrarchy::EncodedPath(
        numerator - p.numerator,
        denominator - p.denominator)
    end
    
    # Finds the mediant of this fraction and +other+.
    def mediant(other)
      Hyrarchy::EncodedPath(
        numerator + other.numerator,
        denominator + other.denominator)
    end
    
    # Returns the fraction immediately after this one in the Farey sequence
    # whose order is this fraction's denominator. This is the find-neighbors
    # algorithm from "Rounding rational numbers using Farey/Cauchy sequence" by
    # Wim Lewis: http://www.hhhh.org/wiml/proj/farey
    def next_farey_fraction
      # Handle the special case of the last fraction.
      return nil if self == Rational(1, 1)
      # Compute the modular multiplicative inverses of the numerator and
      # denominator using an iterative extended Euclidean algorithm. These
      # inverses are the denominator and negative numerator of the fraction
      # preceding this one, modulo the numerator and denominator of this
      # fraction.
      a, b = [numerator, denominator]
      x, lastx, y, lasty = [0, 1, 1, 0]
      while b != 0
        a, b, q = [b, a % b, a / b]
        x, lastx = [lastx - q * x, x]
        y, lasty = [lasty - q * y, y]
      end
      qL, pL = [lastx, -lasty]
      # Find the numerator and denominator of the fraction following this one
      # using the mediant relationship between it, this fraction, and the
      # preceding fraction. The modulo ambiguity is resolved by brute force,
      # which is probably not the smartest way to do it, but it's fast enough.
      i = 0
      while true do
        a = pL + numerator * i
        b = qL + denominator * i
        if (numerator * b - denominator * a == 1) &&
          (Rational(numerator - a, denominator - b).denominator <= denominator)
          return Hyrarchy::EncodedPath(numerator - a, denominator - b)
        end
        i += 1
      end
    end
  end
end
