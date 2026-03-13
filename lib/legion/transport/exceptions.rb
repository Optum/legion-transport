# frozen_string_literal: true

module Legion
  module Exception
    class InvalidTaskStatus < ArgumentError
    end

    class InvalidTaskId < ArgumentError
    end
  end
end
