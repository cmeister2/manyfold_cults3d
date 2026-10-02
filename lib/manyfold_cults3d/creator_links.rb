# frozen_string_literal: true

module ManyfoldCults3d
  module CreatorLinks
    def self.install!
      ::Link.singleton_class.prepend(DeserializerFactory) unless ::Link.singleton_class < DeserializerFactory
    end

    module DeserializerFactory
      def deserializer_for(url:, for_class: nil)
        if for_class.nil? || for_class == ::Creator
          deserializer = CreatorDeserializer.new(uri: url)
          return deserializer if deserializer.valid?(for_class: for_class)
        end
        super
      end
    end
  end
end
