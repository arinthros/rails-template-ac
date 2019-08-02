module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_person

    def connect
      self.current_person = find_verified_person
      logger.add_tags "ActionCable", "Person #{current_person.id}"
    end

    protected

      def find_verified_person
        if current_person = env['warden'].person
          current_person
        else
          reject_unauthorized_connection
        end
      end
  end
end
