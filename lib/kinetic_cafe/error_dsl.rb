module KineticCafe
  # Make defining new children of KineticCafe::Error easy. Adds the
  # #define_error method.
  #
  # If using when Rack is present, useful variant methodss are provided
  # matching Rack status symbol codes. These set the default status to the Rack
  # status.
  #
  #    conflict class: :user # => UserConflict, status: :conflict
  #    not_found class: :post # => PostNotFound, status: :not_found
  module ErrorDSL
    # Convert ThisName to this_name. Uses #underscore if +name+ responds to it.
    # Otherwise, it uses a super naïve version.
    def self.underscore(name)
      name = name.to_s
      if name.respond_to?(:underscore)
        name.underscore.freeze
      else
        name.dup.tap { |n|
          n.gsub!(/[[:upper:]]/) { "_#$&".downcase }
          n.sub!(/^_/, '')
        }.freeze
      end
    end

    # Demodulizes This::Name to just Name. Uses name#demodulize if it is
    # available, or a naïve version otherwise.
    def self.demodulize(name)
      name = name.to_s
      if name.respond_to?(:demodulize)
        name.demodulize.freeze
      else
        name.split(/::/)[-1].freeze
      end
    end

    # Demodulizes and underscores the provided name.
    def self.namify(name)
      underscore(demodulize(name.to_s))
    end

    # Convert this_name to ThisName. Uses #camelize if +name+ responds to it,
    # or a naïve version otherwise.
    def self.camelize(name)
      name = name.to_s
      if name.respond_to?(:camelize)
        name.camelize.freeze
      else
        "_#{name}".gsub(/_([a-z])/i) { $1.upcase }.freeze
      end
    end

    # Define a new error as a subclass of the exception hosting ErrorDSL.
    # Options is a Hash supporting the following values:
    #
    # +status+:: A number or Ruby symbol representing the HTTP status code
    #            associated with this error. If not provided, defaults to
    #            :bad_request. Must be provided if +class+ is provided. HTTP
    #            status codes are defined in Rack::Utils.
    # +key+::    The name of the error class to be created. Provide as a
    #            snake_case value that will be turned into a camelized class
    #            name. Mutually exclusive with +class+.
    # +class+::  The name of the class the error is for. If present, +status+
    #            must be provided to create a complete error class. That is,
    #
    #              define_error class: :object, status: :not_found
    #
    #            will create an +ObjectNotFound+ error class.
    #
    # +header_only+:: Indicates that when this is caught, it should not be
    #                 returned with full details, but shoudl instead be treated
    #                 as a header-only API response.
    def define_error(options)
      fail ArgumentError, 'invalid options' unless options.kind_of?(Hash)
      fail ArgumentError, 'define what error?' if options.empty?

      options = options.dup

      klass = options.delete(:class)
      if klass
        if options.key?(:key)
          fail ArgumentError, ":key conflicts with class:#{klass}"
        end
        status = options[:status]

        key = if status.kind_of?(Symbol) or status.kind_of?(String)
                "#{klass}_#{KineticCafe::ErrorDSL.namify(status)}"
              else
                "#{klass}_#{KineticCafe::ErrorDSL.namify(self.name)}"
              end
      else
        status = options[:status]
        key    = options.fetch(:key) {
          fail ArgumentError, 'one of :key or :class must be provided'
        }.to_s
      end

      key.tap do |k|
        k.squeeze!('_')
        k.gsub!(/^_+/, '')
        k.gsub!(/_+$/, '')
        k.freeze
      end

      error_name = KineticCafe::ErrorDSL.camelize(key)
      i18n_key_base = respond_to?(:i18n_key_base) && self.i18n_key_base ||
        'kcerrors'.freeze
      i18n_key = "#{i18n_key_base}.#{key}".freeze

      if const_defined?(error_name)
        message = "key:#{key} already exists as #{error_name}"
        message << " with class:#{klass}" if klass
        fail ArgumentError, message
      end

      error = Class.new(self)
      error.send :define_method, :name, -> { key }
      error.send :define_method, :i18n_key, -> { i18n_key }

      if options[:header_only]
        error.send :define_method, :header_only?, -> { true }
      end

      if options[:internal]
        error.send :define_method, :internal?, -> { true }
      end

      status ||= defined?(Rack::Utils) && :bad_request || 400
      status.freeze

      error.send :define_method, :default_status, -> { status } if status
      error.send :private, :default_status

      const_set(error_name, error)
    end

    ##
    # 


    private

    ##
    def self.included(_mod)
      fail "#{self} cannot be included"
    end

    ##
    def self.extended(base)
      unless base < ::StandardError
        fail "#{self} cannot extend #{base} (not a StandardError)"
      end

      if defined?(Rack::Utils)
        Rack::Utils::SYMBOL_TO_STATUS_CODE.each do |name, value|
          base.singleton_class.send :define_method, name do |options = {}|
            define_error(options.merge(status: name))
          end

          base.send :define_error, status: name, key: name
        end
      end
    end
  end
end
