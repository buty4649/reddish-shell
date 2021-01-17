module ReddishParser
  class Lexer
    # '<', '<>', '<&', '>', '>>', '>&', '&', '&&', '&>', '|', '||', '|&', ';'
    SIMPLE_TOKEN_PATTERN = '([<>&][>&]?|\|[|&]?|;)'
    QUOTE_WORD_PATTERN = %Q!["']!
    PERCENT_WORD_PATTERN = '(%(!|[qQ]\W))'

    def initialize(line, ifs)
      @line = line.dup
      @last_token = nil
      @statement = nil

      separator = ifs || " \t\n"
      @separator_pattern = "[#{separator}]"
    end

    def get_token
      if @last_token.nil? || @last_token != :word
         read_sperator
      end

      token = eof_token       ||
              simple_token    ||
              number_token    ||
              hyphen_token    ||
              keyword_token   ||
              word_token

      @last_token = token.type
      if token.type == :";" && @statement.nil?
        @last_token = nil
      end

      token
    end

    def eof_token
      if @line.nil? || @line.empty?
        return Token.new(:eof)
      end
    end

    def simple_token
      token = @line.slice!(/^#{SIMPLE_TOKEN_PATTERN}/)
      return unless token
      Token.new(token.to_sym)
    end

    def number_token
      if number = @line.slice!(/\A\d+(?=[<>])/) ||
        ([:"<&", :">&"].include?(@last_token) && number = @line.slice!(/\A\d+/))
        Token.new(:number, number)
      end
    end

    def hyphen_token
      if [:"<&", :">&", :number].include?(@last_token) && @line.slice!("-")
        Token.new(:"-")
      end
    end

    def keyword_token
      return if @last_token && @statement.nil?

      if k = @line.slice!(/\A(if|unless)(?=#{@separator_pattern})/)
        @statement = :if
        Token.new(k.to_sym)
      elsif @line.slice!(/\Athen(?=#{@separator_pattern})?/)
        Token.new(:then)
      elsif k = @line.slice!(/\Ael(se|s?if)(?=#{@separator_pattern})?/)
        Token.new(k.to_sym)
      elsif k = @line.slice!(/\A(fi|end)(?=#{@separator_pattern})?/)
        @statement = nil
        Token.new(k.to_sym)
      end
    end

    def word_token
      word = separator    ||
             quote_word   ||
             percent_word ||
             normal_word
      Token.new(:word, word)
    end

    def separator
      if read_sperator
        [:separator]
      end
    end

    def quote_word
      if s = @line.slice!(/\A#{QUOTE_WORD_PATTERN}/)
        type = s == '"' ? :dquote : :quote
        [type, read_quote_word(s)]
      end
    end

    def percent_word
      if s = @line.slice!(/\A#{PERCENT_WORD_PATTERN}/)
        _, quote, paren = s.split("")
        if quote == "!"
          quote = "Q"
          paren = "!"
        end
        type = {"Q" => :dquote, "q" => :quote}[quote]
        term = {"(" => ")", "[" => "]", "{" => "}", "<" => ">"}[paren] || paren
        [type, read_quote_word(term)]
      end
    end

    def read_quote_word(term)
      t = Regexp.escape(term)
      word = @line.slice!(/\A.*?(?<!\\)#{t}/m)
      raise UnterminatedString.new unless word
      word.delete_suffix!(term).gsub(/\\#{t}/, term)
    end

    def normal_word
      pattern = [SIMPLE_TOKEN_PATTERN, QUOTE_WORD_PATTERN, PERCENT_WORD_PATTERN, @separator_pattern].join("|")
      pos = @line.index(/(?<!\\)(#{pattern})/)
      pos = pos ? pos - 1 : -1
      [:normal, @line.slice!(0..pos)]
    end

    def read_sperator
      @line.slice!(/\A#{@separator_pattern}+/)
    end

    def state
      [@statement]
    end
  end
end
