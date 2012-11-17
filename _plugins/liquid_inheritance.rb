=begin
  Copyright (c) 2009 Dan Webb

  Permission is hereby granted, free of charge, to any person
  obtaining a copy of this software and associated documentation
  files (the "Software"), to deal in the Software without
  restriction, including without limitation the rights to use,
  copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the
  Software is furnished to do so, subject to the following
  conditions:

  The above copyright notice and this permission notice shall be
  included in all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
  OTHER DEALINGS IN THE SOFTWARE.
=end

require 'liquid'

module LiquidInheritance
  
  class BlockDrop < ::Liquid::Drop
    def initialize(block)
      @block = block
    end
    
    def super
      @block.call_super(@context)
    end
  end

  class Block < ::Liquid::Block
    Syntax = /(\w)+/
    attr_accessor :parent
    attr_reader :name
    def initialize(tag_name, markup, tokens)  
      if markup =~ Syntax
        @name = $1
      else
        raise Liquid::SyntaxError.new("Syntax Error in 'block' - Valid syntax: block [name]")
      end
      super if tokens
    end
    def render(context)
      context.stack do
        context['block'] = BlockDrop.new(self)
        render_all(@nodelist, context)
      end
    end
    def add_parent(nodelist)
      if parent
        parent.add_parent(nodelist)
      else
        self.parent = Block.new(@tag_name, @name, nil)
        parent.nodelist = nodelist
      end
    end
    def call_super(context)
      if parent
        parent.render(context)
      else
        ''
      end
    end
  end

end

module LiquidInheritance

  class Extends < ::Liquid::Block
    Syntax = /(#{Liquid::QuotedFragment})/
    def initialize(tag_name, markup, tokens)     
      if markup =~ Syntax 
        @template_name = $1
      else
        raise Liquid::SyntaxError.new("Syntax Error in 'extends' - Valid syntax: extends [template]")
      end
      super
      @blocks = @nodelist.inject({}) do |m, node|
        m[node.name] = node if node.is_a?(::LiquidInheritance::Block); m
      end
    end
    def parse(tokens)
      parse_all(tokens)
    end
    def render(context)
      template = load_template(context)
      parent_blocks = find_blocks(template.root)
      
      @blocks.each do |name, block|
        if pb = parent_blocks[name]
          pb.parent = block.parent
          pb.add_parent(pb.nodelist)
          pb.nodelist = block.nodelist
        else
          if is_extending?(template)
            template.root.nodelist << block
          end
        end
      end
      template.render(context)
    end 
    private
    def parse_all(tokens)
      @nodelist ||= []
      @nodelist.clear
      while token = tokens.shift 
        case token
        when /^#{Liquid::TagStart}/                   
          if token =~ /^#{Liquid::TagStart}\s*(\w+)\s*(.*)?#{Liquid::TagEnd}$/
            # fetch the tag from registered blocks
            if tag = Liquid::Template.tags[$1]
              @nodelist << tag.new($1, $2, tokens)
            else
              # this tag is not registered with the system 
              # pass it to the current block for special handling or error reporting
              unknown_tag($1, $2, tokens)
            end              
          else
            raise Liquid::SyntaxError, "Tag '#{token}' was not properly terminated with regexp: #{TagEnd.inspect} "
          end
        when /^#{Liquid::VariableStart}/
          @nodelist << create_variable(token)
        when ''
          # pass
        else
          @nodelist << token
        end
      end
    end
    def load_template(context)
      source = Liquid::Template.file_system.read_template_file(context[@template_name])      
      Liquid::Template.parse(source)
    end
    def find_blocks(node, blocks={})
      if node.respond_to?(:nodelist)
        node.nodelist.inject(blocks) do |b, node|
          if node.is_a?(LiquidInheritance::Block)
            b[node.name] = node
          else
            find_blocks(node, b)
          end
          
          b
        end
      end
      blocks
    end
    def is_extending?(template)
      template.root.nodelist.any? { |node| node.is_a?(Extends) }
    end
  end

end

module LiquidInheritance

  class Extends < ::Liquid::Block
    def load_template(context)
      root_path = context.registers[:site].source
      file_path = File.join(root_path, context[@template_name])
      source = File.read(file_path.strip)
      Liquid::Template.parse(source)
    end
  end

end

module LiquidInheritance
  autoload :Extends, 'tags/extends'
  autoload :Block, 'tags/block'
end

Liquid::Template.register_tag(:extends, LiquidInheritance::Extends)
Liquid::Template.register_tag(:block, LiquidInheritance::Block)