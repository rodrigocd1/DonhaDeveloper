public with sharing class AC_ControllerConsultaHistoricoFinanceiro 
{
    /** 
    @description  método construtor que inicializa variáveis
    @param 
    @return 
    @author Rodrigo Donha
    @date 10/06/2022
	*/
    public AC_ControllerConsultaHistoricoFinanceiro()
    {
        
    }
    
    @AuraEnabled
    public static AC_ConsultaHistoricoFinanceiro obterHistorico()
    {
        AC_ConsultaHistoricoFinanceiro historico = new AC_ConsultaHistoricoFinanceiro();
        
        return historico;
    }
}