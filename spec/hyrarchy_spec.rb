require File.join(File.dirname(__FILE__), 'spec_helper')

describe Hyrarchy do
  describe "(functionality)" do
    before(:all) do
      Node.delete_all
      
      @roots = [
        Node.create!(:name => 'root 0'),
        Node.create!(:name => 'root 1'),
        Node.create!(:name => 'root 2')
      ]
      @layer1 = [
        Node.create!(:name => '1.0', :parent => @roots[1]),
        Node.create!(:name => '1.1', :parent => @roots[1]),
        Node.create!(:name => '1.2', :parent => @roots[1])
      ]
      @layer2 = [
        Node.create!(:name => '1.0.0', :parent => @layer1[0]),
        Node.create!(:name => '1.0.1', :parent => @layer1[0]),
        Node.create!(:name => '1.1.0', :parent => @layer1[1]),
        Node.create!(:name => '1.1.1', :parent => @layer1[1]),
        Node.create!(:name => '1.2.0', :parent => @layer1[2]),
        Node.create!(:name => '1.2.1', :parent => @layer1[2])
      ]
    
      @roots.collect! {|n| Node.find(n.id)}
      @layer1.collect! {|n| Node.find(n.id)}
      @layer2.collect! {|n| Node.find(n.id)}
    end
  
    it "should find its parent" do
      @layer2[0].parent.should == @layer1[0]
      @layer2[1].parent.should == @layer1[0]
      @layer2[2].parent.should == @layer1[1]
      @layer2[3].parent.should == @layer1[1]
      @layer2[4].parent.should == @layer1[2]
      @layer2[5].parent.should == @layer1[2]
      @layer1.each {|n| n.parent.should == @roots[1]}
      @roots.each {|n| n.parent.should == nil}
    end
  
    it "should find its descendants" do
      returned_descendants = @roots[1].descendants
      returned_descendants.sort! {|a,b| a.name <=> b.name}
      actual_descendants = @layer1 + @layer2
      actual_descendants.sort! {|a,b| a.name <=> b.name}
      returned_descendants.should == actual_descendants
      @roots[0].descendants.should be_empty
      @roots[2].descendants.should be_empty
    end
  
    it "should find its children" do
      @roots[0].children.should be_empty
      @roots[1].children.should == @layer1
      @roots[2].children.should be_empty
      @layer1[0].children.should == [@layer2[0], @layer2[1]]
      @layer1[1].children.should == [@layer2[2], @layer2[3]]
      @layer1[2].children.should == [@layer2[4], @layer2[5]]
      @layer2.each {|n| n.children.should be_empty}
    end
  
    it "should find its ancestors" do
      @layer2[0].ancestors.should == [@layer1[0], @roots[1]]
      @layer2[1].ancestors.should == [@layer1[0], @roots[1]]
      @layer2[2].ancestors.should == [@layer1[1], @roots[1]]
      @layer2[3].ancestors.should == [@layer1[1], @roots[1]]
      @layer2[4].ancestors.should == [@layer1[2], @roots[1]]
      @layer2[5].ancestors.should == [@layer1[2], @roots[1]]
      @layer1.each {|n| n.ancestors.should == [@roots[1]]}
      @roots.each {|n| n.ancestors.should be_empty}
    end
  
    it "should find all root nodes" do
      Node.roots.should == @roots
    end
  end
  
  describe "(data integrity)" do
    before(:each) do
      Node.delete_all
      
      @roots = [
        Node.create!(:name => 'root 0'),
        Node.create!(:name => 'root 1'),
        Node.create!(:name => 'root 2')
      ]
      @layer1 = [
        Node.create!(:name => '1.0', :parent => @roots[1]),
        Node.create!(:name => '1.1', :parent => @roots[1]),
        Node.create!(:name => '1.2', :parent => @roots[1])
      ]
      @layer2 = [
        Node.create!(:name => '1.0.0', :parent => @layer1[0]),
        Node.create!(:name => '1.0.1', :parent => @layer1[0]),
        Node.create!(:name => '1.1.0', :parent => @layer1[1]),
        Node.create!(:name => '1.1.1', :parent => @layer1[1]),
        Node.create!(:name => '1.2.0', :parent => @layer1[2]),
        Node.create!(:name => '1.2.1', :parent => @layer1[2])
      ]
    
      @roots.collect! {|n| Node.find(n.id)}
      @layer1.collect! {|n| Node.find(n.id)}
      @layer2.collect! {|n| Node.find(n.id)}
    end
    
    it "should keep its descendants if it's moved to a different parent" do
      @roots[1].parent = @roots[2]
      @roots[1].save!
      
      returned_descendants = @roots[2].descendants
      returned_descendants.sort! {|a,b| a.name <=> b.name}
      actual_descendants = @layer1 + @layer2 + [@roots[1]]
      actual_descendants.sort! {|a,b| a.name <=> b.name}
      returned_descendants.should == actual_descendants
      @roots[0].descendants.should be_empty
      
      actual_descendants.delete(@roots[1])
      returned_descendants = @roots[1].descendants
      returned_descendants.sort! {|a,b| a.name <=> b.name}
      returned_descendants.should == actual_descendants
    end
    
    it "should destroy its descendants if it's destroyed" do
      @roots[1].destroy
      (@layer1 + @layer2).each do |node|
        lambda { Node.find(node.id) }.should raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
  
  describe "(performance)" do
    SAMPLE_SIZE = 15000
    LAYERS = 10
    
    unless ENV['SKIP_PERFORMANCE']
      it "should scale with constant insertion and access times < 50ms" do
        Node.connection.execute("TRUNCATE TABLE #{Node.quoted_table_name}") rescue Node.delete_all
        insertion_times   = NArray.float(SAMPLE_SIZE)
        parent_times      = NArray.float(SAMPLE_SIZE)
        children_times    = NArray.float(SAMPLE_SIZE)
        ancestors_times   = NArray.float(SAMPLE_SIZE)
        descendants_times = NArray.float(SAMPLE_SIZE)
      
        i = -1
        layer = []
        (SAMPLE_SIZE / LAYERS).times do |j|
          insertion_times[i+=1] = measure_time { layer << Node.create!(:name => j.to_s) }
        end
        (LAYERS-1).times do
          new_layer = []
          (SAMPLE_SIZE / LAYERS).times do |j|
            parent = layer[rand(layer.length)]
            insertion_times[i+=1] = measure_time { new_layer << Node.create!(:name => j.to_s, :parent => parent) }
          end
          layer = new_layer
        end
      
        ids = Node.connection.select_all("SELECT id FROM #{Node.quoted_table_name}")
        ids.collect! {|row| row["id"].to_i}
        SAMPLE_SIZE.times do |i|
          node = Node.find(ids[rand(ids.length)])
          parent_times[i]      = measure_time { node.parent      }
          children_times[i]    = measure_time { node.children    }
          ancestors_times[i]   = measure_time { node.ancestors   }
          descendants_times[i] = measure_time { node.descendants }
        end
      
        [insertion_times, parent_times, children_times, ancestors_times, descendants_times].each do |times|
          (times.mean + 3 * times.stddev).should satisfy {|n| n < 0.05}
          slope, offset = linear_regression(times)
          (slope * 1_000_000 + offset).should satisfy {|n| n < 0.05}
        end
      end
    end
  end
end
