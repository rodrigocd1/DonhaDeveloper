/**************************************************************************
   Desenvolvido por: Felipe Augusto da Silva;
   Data de Criação: 04/10/2013;
   Funcionalidade: Componente de envio de e-mail
   				   Dados: Forma de geração e tipo de campanha. 
   				   http://www.salesforce.com/us/developer/docs/api/Content/sforce_api_calls_sendemail.htm
   				   
**************************************************************************/

public class OzEmail {

	
	
	public static final String PRIORIDADE_ENVIO_EMAIL_MUITO_ALTO = 'Highest';
	public static final String PRIORIDADE_ENVIO_EMAIL_ALTO = 'High';
	public static final String PRIORIDADE_ENVIO_EMAIL_NORMAL = 'Normal';
	public static final String PRIORIDADE_ENVIO_EMAIL_BAIXO = 'Low';
	public static final String PRIORIDADE_ENVIO_EMAIL_MUITO_BAIXO = 'Lowest';



	/** Utilizado para enviar email utilizando o objeto SingleEmailMessage e objeto ozEmailVO preenchido e informado por parâmetro. */
	public static Messaging.SendEmailResult[] enviarEmailSingleEmailMessage( OzEmailVO ozEmailVO )
	{
		try
		{
			
			
			
			Messaging.SingleEmailMessage singleEmailMessage = new Messaging.SingleEmailMessage();
			singleEmailMessage.setToAddresses( montarArrayStringEmailsPara( ozEmailVO ) );
			singleEmailMessage.setSubject( ozEmailVO.assunto );
			singleEmailMessage.setHtmlBody( ozEmailVO.corpoEmail );
			singleEmailMessage.setBccSender( ozEmailVO.enviarCopiaParaRemetente );
			singleEmailMessage.setUseSignature( ozEmailVO.incluirAssinaturaDoUsuarioQueEnviouOEmail );
		
			if ( ozEmailVO.emailRemetenteTodaOrganizacao != null )
			{
				OrgWideEmailAddress orgWideEmailAddress = DAOOrgWideEmailAddress.obterOrgWideEmailAddressPorEmail( ozEmailVO.emailRemetenteTodaOrganizacao );
				
				if ( orgWideEmailAddress != null )
				{
					singleEmailMessage.setOrgWideEmailAddressId( orgWideEmailAddress.Id );
				}
			}
            
            singleEmailMessage.setReferences('rodrigocd01@gmail.com');
            
			if ( ozEmailVO.emailRespostaPara != null )
			{
				singleEmailMessage.setReplyTo( ozEmailVO.emailRespostaPara );	
			}
			
			return Messaging.sendEmail( new Messaging.SingleEmailMessage[] { singleEmailMessage } );
		}
		catch( Exception e )
		{
			throw new OzEmailException( 'Ocorreu um erro inesperado ao tentar enviarEmailSingleEmailMessage.', e );
		}
	}



	/** Utilizado para montar o array de string de e-mails para. */
	private static String[] montarArrayStringEmailsPara( OzEmailVO ozEmailVO )
	{
		String[] listaEmailsPara = null;
		Integer contador = 0;
		if ( ozEmailVO.emailPara != null && ozEmailVO.emailsPara != null )
		{
			listaEmailsPara = new String[ ozEmailVO.emailsPara.size() ];
			for ( String email : ozEmailVO.emailsPara )
			{
				listaEmailsPara[contador] = email;
			}
			contador++;
		}
		else if ( ozEmailVO.emailsPara != null )
		{
			listaEmailsPara = new String[ ozEmailVO.emailsPara.size() ];
			for ( String email : ozEmailVO.emailsPara )
			{
				listaEmailsPara[contador] = email;
			}
			contador++;
		}
		else if ( ozEmailVO.emailPara != null )
		{
			listaEmailsPara = new String[]{ ozEmailVO.emailPara };
		}
		
		return listaEmailsPara;
	}

}