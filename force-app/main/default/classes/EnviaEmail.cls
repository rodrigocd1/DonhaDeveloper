global class EnviaEmail 
{
	
	webservice static string EmailMassa ()
	{
		String mensagem;
		// First, reserve email capacity for the current Apex transaction to ensure
                        
		// that we won't exceed our daily email limits when sending email after
		                        
		// the current transaction is committed.
		Messaging.reserveSingleEmailCapacity(2);
		
		// Processes and actions involved in the Apex transaction occur next,
		// which conclude with sending a single email.
		
		// Now create a new single email message object
		// that will send out a single email to the addresses in the To, CC & BCC list.
		Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
		
		// Strings to hold the email addresses to which you are sending the email.
		String[] toAddresses = new String[] {'user@acme.com'}; 
		String[] ccAddresses = new String[] {'smith@gmail.com'};
		  
		
		// Assign the addresses for the To and CC lists to the mail object.
		mail.setToAddresses(toAddresses);
		mail.setCcAddresses(ccAddresses);
		
		// Specify the address used when the recipients reply to the email. 
		mail.setReplyTo('support@acme.com');
		
		// Specify the name used as the display name.
		mail.setSenderDisplayName('Salesforce Support');
		
		// Specify the subject line for your email address.
		mail.setSubject('New Case Created : ' + case.Id);
		
		// Set to True if you want to BCC yourself on the email.
		mail.setBccSender(false);
		
		// Optionally append the salesforce.com email signature to the email.
		// The email address of the user executing the Apex Code will be used.
		mail.setUseSignature(false);
		
		// Specify the text content of the email.
		mail.setPlainTextBody('Your Case: ' + case.Id +' has been created.');
		
		mail.setHtmlBody('Your case:<b> ' + case.Id +' </b>has been created.<p>'+
		     'To view your case <a href=https://na1.salesforce.com/'+case.Id+'>click here.</a>');
		
		// Send the email you have created.
		Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
				
		return mensagem;	
	}

}