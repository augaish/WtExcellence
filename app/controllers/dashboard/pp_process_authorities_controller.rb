class Dashboard::PpProcessAuthoritiesController < Dashboard::PpProcessDetailController
  def create
    authority = @process.authorities.new(authority_params)
    authority.sort_order = @process.authorities.maximum(:sort_order).to_i + 1

    if authority.save
      back_to_process(notice: t("process_authorities.flash.created"))
    else
      back_to_process(alert: authority.errors.full_messages.to_sentence)
    end
  end

  def destroy
    authority = @process.authorities.find_by(id: params[:id])
    authority&.destroy

    back_to_process(notice: t("process_authorities.flash.deleted"))
  end

  private

  def authority_params
    params.require(:pp_process_authority).permit(:item, :decision, :authority_id)
  end
end
