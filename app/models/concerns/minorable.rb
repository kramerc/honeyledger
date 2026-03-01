module Minorable
  extend ActiveSupport::Concern

  class_methods do
    # Defines minor readers for one or more decimal attributes with a given currency attribute.
    def minorable(*attributes, with: :currency)
      attributes.each do |attribute|
        # def amount_minor
        define_method "#{attribute}_minor" do
          currency = Helpers.dig_send(self, with)
          return nil if currency.nil?
          Helpers.minor_from(send(attribute), currency.decimal_places)
        end
      end
    end

    # Defines decimal readers and writers for one or more minor attributes with a given currency attribute. Validations
    # are also set on the decimal attributes. Writes to the minor attributes from the decimal attributes are deferred
    # until before the resource is saved.
    def unminorable(*attributes, with: :currency)
      attributes.each do |attribute|
        unminored_attribute = attribute.to_s.gsub("_minor", "")

        # def amount
        define_method unminored_attribute do
          unminored = instance_variable_get("@#{unminored_attribute}")
          return unminored if unminored.present?

          currency = Helpers.dig_send(self, with)
          return nil if currency.nil?
          Helpers.unminor_from(send(attribute), currency.decimal_places)
        end

        # def amount=
        # Updates are deferred to a save callback so currency can be set later
        attr_writer unminored_attribute

        # def amount_minor=
        field_writer_method = instance_method("#{attribute}=") if method_defined?("#{attribute}=")
        define_method "#{attribute}=" do |value|
          if field_writer_method
            # Attribute from ActiveModel, class, module, etc.
            field_writer_method.bind(self).call(value)
          else
            # Attribute from ActiveRecord or parent
            super(value)
          end
          instance_variable_set("@#{unminored_attribute}", nil)
        end

        # before_save :set_amount_minor_from_amount
        before_save -> {
          unminored = instance_variable_get("@#{unminored_attribute}")
          currency = Helpers.dig_send(self, with)
          return nil unless unminored && currency

          send("#{attribute}=", Helpers.minor_from(unminored, currency.decimal_places))
        }

        # Validate amount is numeric
        validate -> {
          unminored = instance_variable_get("@#{unminored_attribute}")
          if unminored.present? && !Helpers.numeric?(unminored)
            errors.add(unminored_attribute, "must be a valid number")
          end
        }

        # Validate currency is present if amount is set
        validate -> {
          unminored = instance_variable_get("@#{unminored_attribute}")
          currency = Helpers.dig_send(self, with)
          if unminored.present? && currency.blank?
            errors.add(unminored_attribute, "cannot be saved without #{with.to_s.humanize(capitalize: false)} present")
          end
        }
      end
    end
  end

  module Helpers
    def self.dig_send(resource, path)
      path.to_s.split(".").reduce(resource) { |obj, method| obj.public_send(method) }
    end

    def self.minor_from(amount, decimal_places)
      (amount.to_d * (10 ** decimal_places)).round.to_i
    end

    def self.unminor_from(amount_minor, decimal_places)
      amount_minor.to_d / (10 ** decimal_places)
    end

    def self.numeric?(value)
      BigDecimal(value)
      true
    rescue ArgumentError, TypeError
      false
    end
  end
end
