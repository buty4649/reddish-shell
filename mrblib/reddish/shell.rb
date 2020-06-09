module Reddish
  class Shell
    def initialize(args)
      @opts = getopts(args)
      @job  = JobControl.new
    end

    def getopts(args)
      class << args; include Getopts; end
      opts = args.getopts("c:")
      if opts["?"]
        # Invalid option
        exit(2)
      end
      opts
    end

    def read_from_tty
      linenoise("reddish> ")
    rescue Errno::ENOTTY => e
      # bugs:
      # Errono::NOTTY occurs unintentionally.
      # (e.g. `echo hoge | reddish` )
    end

    def run
      if ENV["REDDISH_PARSER_DEBUG"]
        ReddishParser.debug = true
      end

      if cmd = @opts["c"]
        parse_and_exec(cmd)
      else
        while line = read_from_tty
          parse_and_exec(line)
        end
      end
    end

    def parse_and_exec(line)
      return if line.nil? || line.empty?

      begin
        parse_result = Scanner.new(line).parse

        if parse_result
          @job.run(parse_result)
        end
      rescue => e
        STDERR.puts "#{e.class} #{e.message}"
        if ENV['REDDISH_DEBUG']
          STDERR.puts
          STDERR.puts "backtrace:"
          e.backtrace.each_with_index do |t, i|
            STDERR.puts " [#{i}] #{t}"
          end
        end
      end
    end
  end
end
