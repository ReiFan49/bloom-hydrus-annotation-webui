module Hydrus
  module ClientTags
    def tag_sanitize(tags, context: nil)
      new_tags = tags.dup
      tag_sanitize!(new_tags, context: context)
    end
    def tag_sanitize!(tags, context: nil)
      return unless Array === tags
      tags.replace request(:GET, '/add_tags/clean_tags',
        context: context,
        query: {tags: tags},
      ).fetch('tags')
      tags
    end
    def tag_search(tag, service_name: nil, service_key: nil, context: nil)
      validate_service 'local_tags', name: service_name, key: service_key
      # fail ArgumentError, "expected non-blank String" unless String === tag || tag.empty?

      query = {}
      query[:search] = tag
      query[:tag_service_name] = service_name
      query[:tag_service_key] = service_key
      query.compact!

      request(:GET, '/add_tags/search_tags',
        context: context,
        query: query,
      ).fetch('tags')
    end
    def tag_add_to(tags, name: nil, key: nil, ids: nil, hashes: nil, context: nil)
      tag_complex_build(ids: ids, hashes: hashes, context: context) do
        add_tag *tags, name: nil, key: nil
      end
    end
    def tag_remove_from(tags, name: nil, key: nil, ids: nil, hashes: nil, context: nil)
      tag_complex_build(ids: ids, hashes: hashes, context: context) do
        remove_tag *tags, name: nil, key: nil
      end
    end
    def tag_complex_build(ids: nil, hashes: nil, context: nil, &block)
      scope = Ops::Builder.new
      scope.instance_exec(&block)
      tag_complex_op(scope.build, ids: ids, hashes: hashes, context: context)
    end
    def tag_complex_op(ops, ids: nil, hashes: nil, context: nil)
      ops.select! do |op| Ops::Base === op end
      return if ops.empty?
      simple_op = ops.all? do |op| op.type == 0 end

      query = {}
      query[:hashes] = hashes.to_a if Enumerable === hashes
      query[:file_ids] = ids.to_a  if Enumerable === ids
      if simple_op then
        pop = query[:service_keys_to_tags] = {}
        ops.each do |op|
          op.key = @service_keys.key(op.name) if op.key.nil? || op.key.empty?
          op.key = default_tag_service if op.key.nil?

          pop[op.key] ||= []
          pop[op.key] << op.tag
        end
      else
        pop = query[:service_keys_to_actions_to_tags] = {}
        ops.each do |op|
          op.key = @service_keys.key(op.name) if op.key.nil? || op.key.empty?
          op.key = default_tag_service if op.key.nil?

          pop[op.key] ||= {}
          pop[op.key][op.type] ||= []
          pop[op.key][op.type] << op.to_tag_op
        end
        pop.values.each do |action_map|
          action_map.transform_keys! &:to_s
        end
      end
      query.compact!

      request :POST, '/add_tags/add_tags',
        cbor: false,
        context: context,
        body: query
    end

    module Ops
      Base = Struct.new(:type, :name, :key, :tag, :reason) do
        def reason?
          !reason.nil?
        end
        def to_tag_op
          reason? ?
            [tag, reason] :
            tag
        end
      end unless defined?(Base)
      class Add < Base
        def initialize(*args)
          super(0, *args)
          self.reason = nil
        end
      end
      class Remove < Base
        def initialize(*args)
          super(1, *args)
          self.reason = nil
        end
      end
      class Pend < Base
        def initialize(*args)
          super(2, *args)
          self.reason = nil
        end
      end
      class CancelPend < Base
        def initialize(*args)
          super(3, *args)
          self.reason = nil
        end
      end
      class Petition < Base
        def initialize(*args)
          super(4, *args)
        end
      end
      class CancelPetition < Base
        def initialize(*args)
          super(5, *args)
          self.reason = nil
        end
      end

      class Builder < BasicObject
        def initialize
          @ops = []
        end
        %w(add remove pend cancel_pend petition cancel_petition).each_with_index do |prefix, op_type|
          class_op = [Base, Add, Remove, Pend, CancelPend, Petition, CancelPetition][op_type.succ]
          define_method "#{prefix}_tag" do |*tags, name: nil, key: nil, reason: nil|
            tags.each do |tag|
              @ops << class_op.new(name, key, tag, reason)
            end
          end
        end
        def build
          @ops
        end
      end
    end
    private_constant :Ops
  end
end