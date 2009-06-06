require File.join(File.dirname(__FILE__), 'test_helper')

class EncodedPathTests < Test::Unit::TestCase
  def setup
    @path = Hyrarchy::EncodedPath(5, 7)
  end

  def test_next_farey_fraction
    assert_equal(Rational(3, 4), @path.send(:next_farey_fraction))
  end

  def test_mediant
    assert_equal(Rational(15, 20), @path.send(:mediant, Rational(10, 13)))
  end

  def test_parent
    assert_equal(Rational(2, 3), @path.parent)
  end

  def test_depth
    assert_equal(3, @path.depth)
  end

  def test_first_child
    assert_equal(Rational(8, 11), @path.first_child)
  end
  
  def test_next_sibling
    assert_equal(Rational(7, 10), @path.next_sibling)
  end
  
  def test_inspect
    assert_equal('EncodedPath(5, 7)', @path.inspect)
  end
end
