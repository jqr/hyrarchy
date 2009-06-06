require File.join(File.dirname(__FILE__), 'spec_helper')

describe Hyrarchy::EncodedPath, "an instance of" do
  before(:each) do
    @path = Hyrarchy::EncodedPath(5, 7)
  end

  it "should know the next farey fraction" do
    @path.send(:next_farey_fraction).should == Rational(3, 4)
  end

  it "should know the mediant" do
    @path.send(:mediant, Rational(10, 13)).should == Rational(15, 20)
  end

  it "should know the parent" do
    @path.parent.should == Rational(2, 3)
  end

  it "should know the depth" do
    @path.depth.should == 3
  end

  it "should know the first child" do
    @path.first_child.should == Rational(8, 11)
  end

  it "should know the next sibling" do
    @path.next_sibling.should == Rational(7, 10)
  end

  it "should have a reasonable inspect string" do
    @path.inspect.should == 'EncodedPath(5, 7)'
  end

end