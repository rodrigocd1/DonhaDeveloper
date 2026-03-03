/**************************************************************************
 *  Desenvolvido por: Felipe Augusto da Silva;
 *  Data de Criação: 04/10/2013;
 *  
 *  Padrão Orizonta para envio de e-mails.
 *	Classes: EmailAtualizacaoCadastral(EmailPorProjeto); 
 * 			 OzEmail;
 *			 OzEmailVO;
**************************************************************************/
public class OzEmailVO {

	public Boolean enviarCopiaParaRemetente{ get; set; }
	public Boolean incluirAssinaturaDoUsuarioQueEnviouOEmail{ get; set; }
	public Boolean persistirEmailComoAtividade{ get; set; }

	public String prioridadeDoEmail{ get; set; }
	public String assunto{ get; set; }
	public String textoRemetenteEmailEnviado{ get; set; }
	public String emailRemetenteTodaOrganizacao{get; set;}
	public String corpoEmail{get; set;}
	public String emailRespostaPara{get; set;}
	public String emailPara{get; set;}

	public Id idTemplate{ get; set; }
	
	public List<String> emailsPara{ get; set; }
	public List<String> emailsCopiaOculta{ get; set; }
	public List<String> emailsCopia{get; set;}


/***/
	public OzEmailVO( Boolean enviarCopiaParaRemetente, String assunto, String corpoEmail, List<String> emailsPara,
					  String textoRemetenteEmailEnviado )
	{
		this.enviarCopiaParaRemetente = enviarCopiaParaRemetente;
		this.assunto = assunto;
		this.corpoEmail = corpoEmail;
		this.emailPara = emailPara;
		this.textoRemetenteEmailEnviado = textoRemetenteEmailEnviado;
		this.emailsPara = emailsPara;
		
		this.incluirAssinaturaDoUsuarioQueEnviouOEmail = true;
		this.persistirEmailComoAtividade = true;
		this.prioridadeDoEmail = OzEmail.PRIORIDADE_ENVIO_EMAIL_NORMAL;
		this.emailRemetenteTodaOrganizacao = null;
		this.emailRespostaPara = null;
		this.idTemplate = null;
		this.emailsCopiaOculta = null;
		this.emailsCopia = null;
	}
	
	
/***/	
	public OzEmailVO( Boolean enviarCopiaParaRemetente, String assunto, String corpoEmail, String emailPara, 
					  String emailRemetenteTodaOrganizacao )
	{
		
		
		this.enviarCopiaParaRemetente = enviarCopiaParaRemetente;
		this.assunto = assunto;
		this.corpoEmail = corpoEmail;
		this.emailPara = emailPara;
		this.textoRemetenteEmailEnviado = textoRemetenteEmailEnviado;
		this.emailsPara = emailsPara;
		this.emailRemetenteTodaOrganizacao = emailRemetenteTodaOrganizacao;
		
		this.incluirAssinaturaDoUsuarioQueEnviouOEmail = true;
		this.persistirEmailComoAtividade = true;
		this.prioridadeDoEmail = OzEmail.PRIORIDADE_ENVIO_EMAIL_NORMAL;
		this.emailRespostaPara = null;
		this.idTemplate = null;
		this.emailsCopiaOculta = null;
		this.emailsCopia = null;
	}
	
	
/***/	
	public OzEmailVO( Boolean enviarCopiaParaRemetente, String assunto, String corpoEmail, String emailPara )
	{
		
		
		this.enviarCopiaParaRemetente = enviarCopiaParaRemetente;
		this.assunto = assunto;
		this.corpoEmail = corpoEmail;
		this.emailPara = emailPara;
		this.textoRemetenteEmailEnviado = textoRemetenteEmailEnviado;
		this.emailsPara = emailsPara;
		
		this.incluirAssinaturaDoUsuarioQueEnviouOEmail = true;
		this.persistirEmailComoAtividade = true;
		this.prioridadeDoEmail = OzEmail.PRIORIDADE_ENVIO_EMAIL_NORMAL;
		this.emailRemetenteTodaOrganizacao = null;
		this.emailRespostaPara = null;
		this.idTemplate = null;
		this.emailsCopiaOculta = null;
		this.emailsCopia = null;
	}

}