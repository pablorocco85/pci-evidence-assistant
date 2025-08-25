module PCIEvidence
  module Models
    class PCIRequirementTree
      def initialize
        @requirements = {}
        @children = Hash.new { |h, k| h[k] = [] }
      end
      
      def add_requirement(requirement)
        @requirements[requirement.id] = requirement
        if requirement.parent_id
          @children[requirement.parent_id] << requirement.id
        end
      end
      
      def get_requirement(id)
        @requirements[id]
      end
      
      def get_children(requirement_id)
        @children[requirement_id].map { |id| @requirements[id] }
      end
      
      def get_parent(requirement_id)
        req = @requirements[requirement_id]
        req&.parent_id ? @requirements[req.parent_id] : nil
      end
      
      def get_siblings(requirement_id)
        req = @requirements[requirement_id]
        return [] unless req&.parent_id
        @children[req.parent_id].reject { |id| id == requirement_id }
                               .map { |id| @requirements[id] }
      end

      def all_requirements
        @requirements.values
      end

      def major_requirements
        @requirements.values.select { |r| r.level == :major }
      end

      def requirements_by_level(level)
        @requirements.values.select { |r| r.level == level }
      end

      def requirements_by_type(type)
        @requirements.values.select { |r| r.requirement_type == type }
      end

      def validate_coverage(milestone_requirements)
        missing = milestone_requirements - @requirements.keys
        extra = @requirements.keys - milestone_requirements
        
        {
          complete: missing.empty?,
          missing_requirements: missing,
          extra_requirements: extra,
          total_requirements: @requirements.size,
          expected_requirements: milestone_requirements.size
        }
      end

      def to_h
        {
          requirements: @requirements.transform_values(&:to_h),
          relationships: @children
        }
      end
    end
  end
end
