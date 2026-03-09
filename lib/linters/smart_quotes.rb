module Linters
  class SmartQuotes
    SMART_QUOTES = {
      "\u2018" => { replace: "'", name: "left single quote" },
      "\u2019" => { replace: "'", name: "right single quote" },
      "\u201C" => { replace: '"', name: "left double quote" },
      "\u201D" => { replace: '"', name: "right double quote" },
      "\u2032" => { replace: "'", name: "prime" },
      "\u2033" => { replace: '"', name: "double prime" }
    }.freeze

    PATTERN = Regexp.union(SMART_QUOTES.keys).freeze
    TR_FROM = SMART_QUOTES.keys.join.freeze
    TR_TO = SMART_QUOTES.values.map { |v| v[:replace] }.join.freeze

    GLOB = "**/*.{css,erb,html,js,md,rb,scss,slim,yml}".freeze
    EXCLUDE_PATTERNS = %w[
      log/**/*
      storage/**/*
      tmp/**/*
      vendor/**/*
      lib/linters/**/*
    ].freeze

    COLORS = { red: "\e[31m", green: "\e[32m", cyan: "\e[36m", reset: "\e[0m" }.freeze
    PROGRESS_BATCH_SIZE = 10

    def initialize(root_dir: ".")
      @root = File.expand_path(root_dir)
    end

    def find
      files = file_list
      offenses = scan(files)

      if offenses.any?
        print_offenses(files, offenses)
        1
      else
        puts "\n#{pluralize(files.size, 'file')} inspected, #{COLORS[:green]}no offenses#{COLORS[:reset]} detected"
        0
      end
    end

    def replace
      files = file_list
      modified = 0
      total = 0

      files.each do |path|
        content = File.read(path, encoding: "UTF-8")
        next unless content.match?(PATTERN)

        count = content.count(TR_FROM)
        File.write(path, content.tr(TR_FROM, TR_TO), encoding: "UTF-8")
        puts "✓ Fixed #{pluralize(count, 'smart quote')} in #{relative(path)}"
        modified += 1
        total += count
      end

      puts total.zero? ? "No smart quotes found" : "\nReplaced #{pluralize(total, 'smart quote')} in #{pluralize(modified, 'file')}"
    end

    private
      def file_list
        Dir.glob(File.join(@root, GLOB)).reject do |path|
          rel = relative(path)
          EXCLUDE_PATTERNS.any? do |pattern|
            File.fnmatch?(pattern, rel, File::FNM_PATHNAME | File::FNM_EXTGLOB)
          end
        end
      end

      def relative(path)
        path.delete_prefix("#{@root}/")
      end

      def scan(files)
        puts "Inspecting #{pluralize(files.size, 'file')}"
        prev_sync = $stdout.sync
        $stdout.sync = true

        results = []
        batch_has_offense = false

        begin
          files.each_with_index do |path, index|
            content = File.read(path, encoding: "UTF-8")

            if content.match?(PATTERN)
              batch_has_offense = true
              offenses = []
              line_num = 1
              line_start = 0

              content.scan(PATTERN) do
                pos = Regexp.last_match.begin(0)
                while (nl = content.index("\n", line_start)) && nl < pos
                  line_num += 1
                  line_start = nl + 1
                end
                offenses << { line: line_num, col: pos - line_start + 1, quote: Regexp.last_match[0] }
              end

              results << { path: path, offenses: offenses }
            end

            if (index + 1) % PROGRESS_BATCH_SIZE == 0
              print batch_has_offense ? "#{COLORS[:red]}F#{COLORS[:reset]}" : "#{COLORS[:green]}.#{COLORS[:reset]}"
              batch_has_offense = false
            end
          end

          # Print remaining batch
          if files.size % PROGRESS_BATCH_SIZE != 0
            print batch_has_offense ? "#{COLORS[:red]}F#{COLORS[:reset]}" : "#{COLORS[:green]}.#{COLORS[:reset]}"
          end
        ensure
          $stdout.sync = prev_sync
        end
        puts
        results
      end

      def print_offenses(files, results)
        count = results.sum { |r| r[:offenses].size }
        puts "\nOffenses:\n\n"

        results.each do |r|
          r[:offenses].each do |o|
            name = SMART_QUOTES[o[:quote]][:name]
            puts "#{COLORS[:cyan]}#{relative(r[:path])}#{COLORS[:reset]}:#{o[:line]}:#{o[:col]}: #{COLORS[:red]}F#{COLORS[:reset]}: #{name} #{o[:quote]}"
          end
          puts
        end

        puts "#{pluralize(files.size, 'file')} inspected, #{COLORS[:red]}#{pluralize(count, 'offense')}#{COLORS[:reset]} detected"
        puts "\nTo fix these offenses, run:\n\n  bin/smart_quotes replace\n\n"
      end

      def pluralize(count, singular)
        count == 1 ? "#{count} #{singular}" : "#{count} #{singular}s"
      end
  end
end
