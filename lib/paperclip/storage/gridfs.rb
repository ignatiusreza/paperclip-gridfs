begin
  require 'mongoid-grid_fs'
rescue LoadError => e
  e.message << " (You may need to install the mongoid-grid_fs gem)"
  raise e
end

module Paperclip
  module Storage
    # MongoDB's GridFS storage system (http://www.mongodb.org/display/DOCS/GridFS) uses
    # a chunking strategy to store files in a mongodb database.
    #
    module Gridfs
      GRID = ::Mongoid::GridFs

      def exists? style = default_style
        if original_filename
          !GRID.find(path(style)).nil?
        else
          false
        end
      end

      def copy_to_local_file style = default_style, local_dest_path = nil
        @queued_for_write[style] ||
          (local_dest_path.blank? ?
            ::Paperclip::Tempfile.new(original_filename).tap do |tf|
              tf.binmode
              tf.write(GRID[path(style)].data)
              tf.close
            end :
            ::File.open(local_dest_path, 'wb').tap do |tf|
              begin
                tf.write(GRID[path(style)].data)
              rescue
                Rails.logger.info "[Paperclip] Failed reading #{path(style)}"
              end
              tf.close
            end)
      end

      def flush_writes #:nodoc:
        @queued_for_write.each do |style, file|
          log("saving #{path(style)}")
          begin
            GRID[path(style)] = file
          rescue
            Rails.logger.info "[Paperclip] Failed saving #{path(style)}"
          end
        end
        after_flush_writes # allows attachment to clean up temp files
      ensure
        @queued_for_write = {}
      end

      def flush_deletes #:nodoc:
        @queued_for_delete.each do |path|
          begin
            log("deleting #{path}")
            val = GRID.find(path)
            if !val.nil?
              val.delete
            end
          rescue Errno::ENOENT => e
            # ignore file-not-found, let everything else pass
          end
        end
      ensure
        @queued_for_delete = []
      end
    end
  end
end
