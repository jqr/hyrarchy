require 'rational'

module Hyrarchy
  def self.EncodedPath(n, d)
    EncodedPath.reduce n, d
  end

  class EncodedPath < Rational
    ROOT = Hyrarchy::EncodedPath(0, 1)

    def parent(root_is_nil = true)
      r = next_farey_fraction
      p = Hyrarchy::EncodedPath(numerator - r.numerator, denominator - r.denominator)
      if root_is_nil && p == ROOT
        nil
      else
        p
      end
    end

    def depth
      n = self
      depth = 0
      while n != ROOT
        n = n.parent(false)
        depth += 1
      end
      depth
    end

    def first_child
      mediant(next_farey_fraction)
    end

    def next_sibling
      parent(false).mediant(self)
    end

    def mediant(other)
      Hyrarchy::EncodedPath(numerator + other.numerator, denominator + other.denominator)
    end

    def next_farey_fraction
      a, b = [numerator, denominator]
      x, lastx, y, lasty = [0, 1, 1, 0]
      while b != 0
        a, b, q = [b, a % b, a / b]
        x, lastx = [lastx - q * x, x]
        y, lasty = [lasty - q * y, y]
      end
      qL, pL = [lastx, -lasty]
      # There's probably a smarter way to do this.
      i = 0
      while true do
        a = pL + numerator * i
        b = qL + denominator * i
        if (numerator * b - denominator * a == 1) && (Rational(numerator - a, denominator - b).denominator <= denominator)
          return Hyrarchy::EncodedPath(numerator - a, denominator - b)
        end
        i += 1
      end
    end
  end
end
