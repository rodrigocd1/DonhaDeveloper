public class ControllerAberturaChamado 
{
    public String nome					{get;set;}
    public String email					{get;set;}
    public String descricao				{get;set;}
    public String link					{get;set;}
    public String visaoGeral 			{get;set;}    
    public String perfis 				{get;set;}
    public List<String> listSimulacao 	{get;set;}
    public String resultadoEsperado 	{get;set;}
    
    
    public Attachment anexo {get;set;}
        
        
    public ControllerAberturaChamado()
    {
        
    }
    
    public void enviarEmail()
    {
        OzEmailVO ozEmailVo = new OzEmailVO(true,'assunto','corpo','rdonha@avanxo.com',null);
        OzEmail.enviarEmailSingleEmailMessage( ozEmailVo );
    }    
    
    public static void criaEmail(String contato,String emailResp,String nomeEnvio,String assunto,String corpoEmail) 
    {
       //Define estância do objeto de envio de e-mail
       Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
       //Define para qual usuário o e-mail será enviado
       String[] toAddresses = new String[] {contato};
       email.setToAddresses(toAddresses);
       //Define quem receberá a resposta do e-mail
       email.setReplyTo(emailResp);
       //Define o nome de quem esta enviando o e-mail
       email.setSenderDisplayName(nomeEnvio);
       //Define o assunto
       email.setSubject(assunto);
       // Assinatura
       email.setUseSignature(true);
       //Define corpo do e-mail em HTML
       email.setHtmlBody(corpoEmail);
       //Envia o e-mail
       Messaging.sendEmail(new Messaging.SingleEmailMessage[] { email });
    }
    
}