# frozen_string_literal: true

module AnalyticsOps
  module Clients
    # Shared fail-closed mapping from official-client transport failures to public gem errors.
    module ErrorTranslation
      NETWORK_FAILURE = /
        Google::Cloud::|GRPC::|Gapic::|Faraday::|HTTP|SocketError|EOFError|OpenSSL::SSL::|
        Errno::E(?:PIPE|CONNABORTED|CONNRESET|CONNREFUSED|HOSTUNREACH|NETUNREACH|ADDRNOTAVAIL)
      /x

      module_function

      def call
        yield
      rescue AnalyticsOps::Error
        raise
      rescue StandardError => error
        translated = error_class(error.class.name)
        raise unless translated

        raise translated.new(
          Redaction.message(error.message),
          remote_reason: structured_value(error, :reason),
          remote_metadata: structured_value(error, :error_metadata),
          remote_code: structured_value(error, :code)
        )
      end

      def error_class(name)
        case name
        when /Unauthenticated|Google::Auth|Signet::Authorization|Gapic::UniverseDomainMismatch/
          AuthenticationError
        when /PermissionDenied|Forbidden/
          AuthorizationError
        when /ResourceExhausted|TooManyRequests/
          QuotaError
        when /DeadlineExceeded|Timeout|ETIMEDOUT/
          TimeoutError
        when /InvalidArgument|FailedPrecondition|NotFound|AlreadyExists|Google::Protobuf::/
          InvalidRequestError
        when NETWORK_FAILURE
          RemoteError
        end
      end
      private_class_method :error_class

      def structured_value(error, method)
        error.public_send(method) if error.respond_to?(method)
      rescue StandardError
        nil
      end
      private_class_method :structured_value
    end
    private_constant :ErrorTranslation
  end
end
