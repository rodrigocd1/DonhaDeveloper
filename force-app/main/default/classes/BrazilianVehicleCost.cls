//Rodrigo Donha
//Created Date : 09-17-2023
//
public class BrazilianVehicleCost 
{
    
        // 
   public static Decimal custoRevisaoPorKM( Decimal valorMedioRevisao , Decimal KilometroRodadoAnual  )
   {
       Decimal custoRevisaoPorKM = 0;
       
       Decimal revisaoCadaXMeses = ( KilometroRodadoAnual / 10000 );             
       
       Decimal revisoesPorAno = 0;
       
       Decimal custoAnualcomRevisao = 0;       
    
       
       if( revisaoCadaXMeses.intValue() > 0 )
       {
       		revisoesPorAno =  12 / revisaoCadaXMeses.intValue() ;    
       }
       else
       {
			revisoesPorAno = 0 ;          
       }
       
       system.debug('Você faz revisão a cada ' + revisaoCadaXMeses + ' meses se fizer a cada 10 mil KM');		
       
       custoAnualcomRevisao = revisoesPorAno * valorMedioRevisao;
       
       system.debug('Seu custo anual com revisão é R$' + custoAnualcomRevisao);
       
       custoRevisaoPorKM = custoAnualcomRevisao / KilometroRodadoAnual;
       
       system.debug('custo Da Revisao Por KM rodado = R$' + custoRevisaoPorKM  );
       
       return custoRevisaoPorKM;
   }
    
    // 
   public static Decimal custoSeguroPorKM( Decimal valorSeguro , Decimal KilometroRodadoAnual  )
   {
       Decimal custoSeguroPorKM = 0;
       
       custoSeguroPorKM = valorSeguro / KilometroRodadoAnual ;
       
       system.debug('custo Do Seguro Por KM rodado = R$' + custoSeguroPorKM  );
       
       return custoSeguroPorKM;
   }
    
	  
   // 
   public static Decimal custoGasolinaPorKM( Decimal valorMediaGasolina , Decimal kmPorLitro  )
   {
       Decimal custoGasolinaPorKM = 0;
       
       custoGasolinaPorKM = valorMediaGasolina / kmPorLitro ;
       
       system.debug('custo Gasolina Por KM = R$' + custoGasolinaPorKM  );
       
       return custoGasolinaPorKM;
   }
    
   // 
   public static Decimal custoKmRodadoPneu( Decimal valorPneu, Decimal KilometroRodadoAnual ,   Decimal KMduracaoPneus  )
   {
       Decimal custoPneuKMrodado = 0;
       
       custoPneuKMrodado = valorPneu / 40000 ;//Considerando que um pneu dura 40 Mil KM mais tem pneu que dura mais
       
       custoPneuKMrodado = custoPneuKMrodado * 4;
       
       system.debug('custo Pneu KM rodado = R$' + custoPneuKMrodado  );
       
       Decimal mesesDuracaoPneus; 
       
       if( KMduracaoPneus > 0)
       {
       		mesesDuracaoPneus = KMduracaoPneus / ((KilometroRodadoAnual / 12));
            system.debug('Seu pneus em tese vão durar ' + mesesDuracaoPneus.intValue() + ' meses se eles rodarem os ' + KMduracaoPneus + ' KM informados');
       }
       else
       {
           mesesDuracaoPneus = 40000 / ((KilometroRodadoAnual / 12));
            system.debug('Seu pneus em tese vão durar ' + mesesDuracaoPneus.intValue() + ' meses se eles rodarem apenas 40 mil KM ');
       }       
      
       
       Decimal anosDuracaoPneu = mesesDuracaoPneus/12;
       
       system.debug('ou seja vai durar ' + anosDuracaoPneu + ' Anos');
       
       return custoPneuKMrodado;
   }
   
    
   //
   public static Decimal IPVA( Decimal valorVeiculo , String UF , Decimal KilometroRodadoAnual)
   {
       Decimal IPVA = 0;
       Decimal IPVAporKM = 0 ;
       
       
       if( UF == 'SP')
       {
         system.debug('IPVA = R$ ' + valorVeiculo * 0.04  );
       	 IPVA = valorVeiculo * 0.04;        
       }
       
       IPVAporKM = IPVA / KilometroRodadoAnual;
       
       system.debug('O custo do IPVA por KM é ' + IPVAporKM);
       
       
       return IPVAporKM;
   }
}