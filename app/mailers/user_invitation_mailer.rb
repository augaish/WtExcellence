class UserInvitationMailer < ApplicationMailer
  def invitation_email(user, company = nil)
    @user = user
    @company = company
    @invitation_token = user.invitation_token
    @invitation_url = accept_invitation_url(@invitation_token)
    
    subject = if @company
      "You've been invited to join #{@company.name}"
    elsif user.delegated_admin?
      "You've been invited as a Delegated Admin"
    else
      "You've been invited to join Way To Excellence"
    end
    
    mail(
      to: @user.email,
      subject: subject
    )
  end
end

