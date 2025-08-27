class Item < ApplicationRecord
  belongs_to :character

  validates :name, presence: true
  validates :description, presence: true

  scope :for_character, ->(character) { where(character: character) }
  scope :by_name, ->(name) { where(name: name) }

  def properties_hash
    return {} if properties.blank?
    JSON.parse(properties)
  end

  def properties_hash=(props)
    self.properties = props.to_json
  end

  def add_property(key, value)
    current_properties = properties_hash
    current_properties[key] = value
    self.properties_hash = current_properties
  end

  def get_property(key)
    properties_hash[key]
  end

  def has_property?(key)
    properties_hash.key?(key)
  end
end
