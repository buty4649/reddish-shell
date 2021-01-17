module ReddishParser
  class ParserError < StandardError; end
  class UnknownType < StandardError; end
  class SyntaxError < StandardError; end
  class UnterminatedString < StandardError; end
  class UnexpectedKeyword < StandardError; end
end
