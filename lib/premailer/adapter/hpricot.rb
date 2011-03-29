
module Adapter
	module Hpricot
	
	  # Merge CSS into the HTML document.
  #
  # Returns a string.
  def to_inline_css
    doc = @processed_doc
    @unmergable_rules = CssParser::Parser.new
    
    # Give all styles already in style attributes a specificity of 1000 
    # per http://www.w3.org/TR/CSS21/cascade.html#specificity
    doc.search("*[@style]").each do |el| 
      el['style'] = '[SPEC=1000[' + el.attributes['style'] + ']]'
    end

    # Iterate through the rules and merge them into the HTML
    @css_parser.each_selector(:all) do |selector, declaration, specificity|
      # Save un-mergable rules separately
      selector.gsub!(/:link([\s]*)+/i) {|m| $1 }

      # Convert element names to lower case
      selector.gsub!(/([\s]|^)([\w]+)/) {|m| $1.to_s + $2.to_s.downcase }
      
      if selector =~ Premailer::RE_UNMERGABLE_SELECTORS
        @unmergable_rules.add_rule_set!(CssParser::RuleSet.new(selector, declaration)) unless @options[:preserve_styles]
      else
        begin
          # Change single ID CSS selectors into xpath so that we can match more 
          # than one element.  Added to work around dodgy generated code.
          selector.gsub!(/\A\#([\w_\-]+)\Z/, '*[@id=\1]')

          doc.search(selector).each do |el|
            if el.elem? and (el.name != 'head' and el.parent.name != 'head')
              # Add a style attribute or append to the existing one  
              block = "[SPEC=#{specificity}[#{declaration}]]"
              el['style'] = (el.attributes['style'].to_s ||= '') + ' ' + block
            end
          end
        rescue Hpricot::Error, RuntimeError, ArgumentError
          $stderr.puts "CSS syntax error with selector: #{selector}" if @options[:verbose]
          next
        end
      end
    end

    # Read STYLE attributes and perform folding
    doc.search("*[@style]").each do |el|
      style = el.attributes['style'].to_s
      
      declarations = []

      style.scan(/\[SPEC\=([\d]+)\[(.[^\]\]]*)\]\]/).each do |declaration|
        rs = CssParser::RuleSet.new(nil, declaration[1].to_s, declaration[0].to_i)
        declarations << rs
      end

      # Perform style folding
      merged = CssParser.merge(declarations)
      merged.expand_shorthand!
           
      # Duplicate CSS attributes as HTML attributes
      if Premailer::RELATED_ATTRIBUTES.has_key?(el.name)       
        Premailer::RELATED_ATTRIBUTES[el.name].each do |css_att, html_att|
          el[html_att] = merged[css_att].gsub(/;$/, '').strip if el[html_att].nil? and not merged[css_att].empty?
        end
      end
      
      merged.create_dimensions_shorthand!

      # write the inline STYLE attribute
      el['style'] = Premailer.escape_string(merged.declarations_to_s)
    end

    doc = write_unmergable_css_rules(doc, @unmergable_rules)

    doc.search('*').remove_class if @options[:remove_classes]  
    
    if @options[:remove_ids]
      # find all anchor's targets and hash them
      targets = []
      doc.search("a[@href^=#]").each do |el|
        target = el.get_attribute('href')[1..-1]
        targets << target
        el.set_attribute('href', "#" + Digest::MD5.hexdigest(target))
      end
      # hash ids that are links target, delete others
      doc.search("*[@id]").each do |el|
        id = el.get_attribute('id')
        if targets.include?(id)
          el.set_attribute('id', Digest::MD5.hexdigest(id))
        else
          el.remove_attr('id')
        end
      end
    end

    @processed_doc = doc

    @processed_doc.to_original_html
  end
	
	# Create a <tt>style</tt> element with un-mergable rules (e.g. <tt>:hover</tt>) 
  # and write it into the <tt>body</tt>.
  #
  # <tt>doc</tt> is an Hpricot document and <tt>unmergable_css_rules</tt> is a Css::RuleSet.
  #
  # Returns an Hpricot document.
  def write_unmergable_css_rules(doc, unmergable_rules) # :nodoc:
    if head = doc.search('head')
      styles = ''
      unmergable_rules.each_selector(:all, :force_important => true) do |selector, declarations, specificity|
        styles += "#{selector} { #{declarations} }\n"
      end    

      unless styles.empty?
        style_tag = "\n<style type=\"text/css\">\n#{styles}</style>\n"
        head.html.empty? ? head.inner_html(style_tag) : head.append(style_tag)
      end
    else
      $stderr.puts "Unable to write unmergable CSS rules: no <head> was found" if @options[:verbose]
    end
    doc
  end

	
    # Converts the HTML document to a format suitable for plain-text e-mail.
    #
		# If present, uses the <body> element as its base; otherwise uses the whole document.
		#
		# Returns a string.
		def to_plain_text
			html_src = ''
			begin
				html_src = @doc.search("body").inner_html
			rescue; end

			html_src = @doc.to_html unless html_src and not html_src.empty?
			convert_to_text(html_src, @options[:line_length], @html_encoding)
		end	
	
	
	  # Returns the original HTML as a string.
		def to_s
			@doc.to_original_html
		end

	  # Load the HTML file and convert it into an Hpricot document.
		#
		# Returns an Hpricot document.
		def load_html(input) # :nodoc:
			thing = nil
			
			# TODO: duplicate options
			if @options[:with_html_string] or @options[:inline] or input.respond_to?(:read)
				thing = input
				elsif @is_local_file
				@base_dir = File.dirname(input)
				thing = File.open(input, 'r')
				else
				thing = open(input)
			end

			# TODO: deal with Hpricot seg faults on empty input
			thing ? Hpricot(thing) : nil  
		end
		
	end
end
