class PerDomainLogger < Logger
  def initialize(log_dir = Rails.root.join('log'))
    @log_dir = log_dir
    FileUtils.mkdir_p(@log_dir)
    @loggers = {}
    @fallback = Logger.new(File.join(@log_dir, "production.log"))
    @fallback.formatter = Rails.application.config.log_formatter
    @mutex = Mutex.new

    super(File::NULL)
  end

  def add(severity, message = nil, progname = nil, &block)
    logger_for_current_domain.add(severity, message, progname, &block)
  end

  def close
    @mutex.synchronize do
      @loggers.each_value(&:close)
      @loggers.clear
    end
    @fallback.close
  end

  private

  def logger_for_current_domain
    domain = Entity.current&.domain

    return @fallback if domain.blank?

    @mutex.synchronize do
      @loggers[domain] ||= build_logger(domain)
    end
  end

  def build_logger(domain)
    sanitized = domain.gsub(/[^a-zA-Z0-9.\-_]/, '_')
    path = File.join(@log_dir, "#{sanitized}.log")
    logger = Logger.new(path, 'daily')
    logger.formatter = Rails.application.config.log_formatter
    logger.level = Rails.logger.level
    logger
  end
end
