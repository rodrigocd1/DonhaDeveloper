import { LightningElement, api, wire, track } from 'lwc';
import { getDataHandler } from 'omnistudio/utility';
import horarioMovimentacao from "@salesforce/label/c.CKBR_CL_Horario_Movimentacao";
import horarioBR from "@salesforce/label/c.CKBR_CL_Horario";
import percentualCDI from "@salesforce/label/c.CKBR_CL_PercentualCDI"; 
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getToastMessage from '@salesforce/apex/CKBR_CTL_ProductShowCaseApply.getParametrizacoesSinv';

export default class CkBR_LWC_ProductShowCaseConfirm extends LightningElement {
    @api isShowConfirm;
    @api investmentSelected;

    @track valorAplicacao = '';
    @track valorPercentualCDI = '';
    @track valorVencimentoAplicacao = '';
    @track valorVencimentoCarencia = '';
    @track valorDiasCarencia = '';
    @track valorPrazoDiasCorridos = '';
    @track valorPrazoDiasUteis = '';
    @track valorDataInvestimento = '';
    @track horarioMovimentacao = '';
    @track messageType = 'ckBR_LWC_ProductShowCaseConfirm'; 
    @track developerName = 'successProductShowCaseConfirm'; 

    label = {
        percentualCDI,
        horarioMovimentacao,
        horarioBR
    }


    connectedCallback() {
        this.isShowAplicar = true;

        this.nome = this.investmentSelected?.nome || 'LCI 5 anos';
        this.aplicacaoMinima = this.investmentSelected?.aplicacaoMinima || 'R$ 10.000,00';
        this.horarioMovimentacao = this.investmentSelected?.horarioMovimentacao || '08h00 às 16h30';
        this.classificacaoTributaria = this.investmentSelected?.classificacaoTributaria || 'CDI/SELIC';
        this.iRendimento = this.investmentSelected?.iRendimento || 'de 22.5% a 15%';
        this.iof = this.investmentSelected?.iof || 'R$ 1.000,00';
        this.risco = this.investmentSelected?.risco || 'Muito baixo';
        this.creditoContaCorrente = this.investmentSelected?.creditoContaCorrente || '1 dia útil';
        this.regasteMinimo = 'R$ 10.000.00';
        this.saldoMinimo = 'R$ 1000.00';
        this.carencia = 'Longo Prazo';
 
        // Formatar as datas
        this.valorVencimentoAplicacao = this.formatDate(this.investmentSelected?.valueVencimentoAplicacao);
        this.valorVencimentoCarencia = this.formatDate(this.investmentSelected?.valueVencimentoCarencia);
        this.valorDataInvestimento = this.formatDate(this.investmentSelected?.valueDataInvestimento); 
    }

    formatDate(dateString) {
        if (!dateString) return '';
        const date = new Date(dateString);
        return new Intl.DateTimeFormat('pt-BR').format(date);
    }

    handleEdit(event) {
        const selectedEvent = new CustomEvent("selectededit", { detail: this.isShowConfirm });
        this.dispatchEvent(selectedEvent);  
    }

    closeApply(event){
        const selectedEvent = new CustomEvent("selectedconfirm", { detail: this.isShowConfirm });
        this.dispatchEvent(selectedEvent);  
    }

    handleApply(event) {


        

        

        getToastMessage({ aMessageType: this.messageType, 
                         aDeveloperName : this.developerName 
         }) 
        .then(result => { 
            if (result) {  
                // Exibe a mensagem de showToast com os dados retornados
                console.log('result' + JSON.stringify(result)); 
                    console.log('entrou no for element');  
                    if(result.DeveloperName == 'successProductShowCaseConfirm'){ 
                        console.log('result.DeveloperName >>> ' + result.DeveloperName); 
                        this.showToastMessage(result.CKBR_CMT_TXT_SuccessMessage__c, result.CKBR_CMT_TXT_InfoMessage__c, result.Label);
                        const selectedEvent = new CustomEvent("selectedconfirm", { detail: this.isShowConfirm });
                        this.dispatchEvent(selectedEvent);   
                    }  

            } else {
                // Se nenhum dado for retornado, exibe uma mensagem de erro padrão
                getToastMessage({ aMessageType: this.messageType }) 
                .then(result => { 
                        if(result.DeveloperName == 'warningProductShowCaseConfirm'){ 
                            console.log('result.DeveloperName >>> ' + result.DeveloperName); 
                            this.showToastMessage(result.CKBR_CMT_TXT_WarningMessage__c, result.CKBR_CMT_TXT_InfoMessage__c, result.Label);
                        }
                }); 
                
            }
        })
        .catch(error => {
            // Lidar com erros de chamada ao Apex
            console.error('Error fetching toast message: ', error);
            getToastMessage({ aMessageType: this.messageType }) 
            .then(result => { 
                    if(result.DeveloperName == 'errorProductShowConfirm'){ 
                        console.log('result.DeveloperName >>> ' + result.DeveloperName);  
                        this.showToastMessage(result.CKBR_CMT_TXT_ErrorMessage__c, result.CKBR_CMT_TXT_InfoMessage__c, result.Label);
                    }  
               
            }); 
            
        }); 

        
  
        //this.getOmniStudioVIPFinished(); //irei terminar assim que o serviço estiver pronto. 
    }


    showToastMessage(titleMsg, messageMsg, variantMsg) {
        const evt = new ShowToastEvent({
            title: titleMsg,
            message: messageMsg,
            variant: variantMsg,
        });
        this.dispatchEvent(evt);
    }





    
    getOmniStudioVIPFinished() { 
        this.spinnerTable = true;
        let optionsMap = {    
            "aRecordId" : this.investmentSelected.idRegistro,
            "valorAplicacao": this.valorAplicacao, 
        "valorPercentualCDI" : this.valorPercentualCDI,
        "valorVencimentoAplicacao" : this.valorVencimentoAplicacao,
        "valorVencimentoCarencia" : this.valorVencimentoCarencia,
        "valorDiasCarencia" : this.valorDiasCarencia,
        "valorPrazoDiasCorridos" : this.valorPrazoDiasCorridos,
        "valorPrazoDiasUteis" : this.valorPrazoDiasUteis,
        "valorDataInvestimento" : this.valorDataInvestimento,
        "valorDataInvestimento" : this.investmentSelected.valueCustoBanco,
        "valorCustoBanco" : this.investmentSelected.valueCustoBanco,
        "valorTaxa252Cliente" : this.investmentSelected.valueTaxa252Cliente,
        "valueTaxa360Cliente" : this.investmentSelected.valueTaxa360Cliente,
        "valorTaxa252Banco" : this.investmentSelected.valueTaxa252Banco,
        "valorTaxa360Banco" : this.investmentSelected.valueTaxa360Banco,
        "valorSpreadBanco" : this.investmentSelected.valueSpreadBanco,
        "valorResultadoFinanceiro" : this.investmentSelected.valueResultadoFinanceiro,
        "valorCDINegociado" : this.investmentSelected.valueCDINegociado
    };  
   
        let vipRes = JSON.stringify({ 
            type: 'integrationprocedure',
            value: {
                ipMethod: 'CKBR_VitrineProdutoAplicarRendaFixa',  
                inputMap: JSON.stringify(optionsMap), 
            },
        });
        getDataHandler(vipRes).then((data) => { 
            this.isShowAplicar = false;
            const selectedEvent = new CustomEvent('selected', {
                detail: this.isShowAplicar
            });
            this.dispatchEvent(selectedEvent);
            this.showToastMessage('Sucesso', 'Aplicação Financeira realizada com sucesso', 'success');
            setTimeout(() => {
                this.spinnerTable = false;
            }, 2000);
        }).catch((error) => {
            console.error('Error fetching data', error);
            this.showToastMessage('Erro', 'Erro no serviço da Integration Procedure de Renda Alta', 'error');
        });
    }
}