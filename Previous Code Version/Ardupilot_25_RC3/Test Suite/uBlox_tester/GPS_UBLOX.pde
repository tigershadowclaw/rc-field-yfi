#if GPS_PROTOCOL == 2
/****************************************************************
 * Here you have all the parsing stuff for uBlox
 ****************************************************************/
//You have to disable all the other string, only leave this ones:

//NAV - POSLLH Geodetic Position Solution, PAGE 66 of datasheet
//NAV - VELNED Velocity Solution in NED, PAGE 71 of datasheet
//NAV - STATUS Receiver Navigation Status, PAGE 67 of datasheet

 /*
 GPS_fix Type 
 - 0x00 = no fix
 - 0x01 = dead reckonin
 - 0x02 = 2D - fix
 - 0x03 = 3D - fix
 - 0x04 = GPS + dead re
 - 0x05 = Time only fix
 - 0x06..0xff = reserved
 */

//Luckly uBlox has internal EEPROM so all the settings you change will remain forever.	Not like the SIRF modules! =P

void init_gps(void)
{
	pinMode(12, OUTPUT);//Status led
	Serial.begin(THIRTY_EIGHT_K_BAUD); //Universal Sincronus Asyncronus Receiveing Transmiting 
	wait_for_GPS_fix();
}

void fast_init_gps(void)
{
	pinMode(12, OUTPUT);//Status led
	Serial.begin(THIRTY_EIGHT_K_BAUD); //Universal Sincronus Asyncronus Receiveing Transmiting 
}

/****************************************************************
 * 
 ****************************************************************/
void decode_gps(void)
{
	static unsigned long GPS_timer = 0;
	static byte GPS_step = 0;
	byte data;
	int numc;
	
	numc = Serial.available();
	if (numc > 0){
		delay(3); // added delay to help with servo hangs
		for (int i=0; i<numc; i++){	// Process bytes received
			data = Serial.read();
			switch(GPS_step){		 //Normally we start from zero. This is a state machine
				case 0:	
					if(data==0xB5)	// UBX sync char 1
						GPS_step++;	 //ooh! first data packet is correct. Jump to the next step.
					break; 
				case 1:	
					if(data==0x62)	// UBX sync char 2
						GPS_step++;	 //ooh! The second data packet is correct, jump to the step 2
					else 
						GPS_step=0;	 //Nope, incorrect. Restart to step zero and try again.		 
					break;
				case 2:
					UBX_class = data;
					checksum(UBX_class);
					GPS_step++;
					break;
				case 3:
					UBX_id = data;
					checksum(UBX_id);
					GPS_step++;
					break;
				case 4:
					UBX_payload_length_hi = data;
					checksum(UBX_payload_length_hi);
					GPS_step++;
					break;
				case 5:
					UBX_payload_length_lo = data;
					checksum(UBX_payload_length_lo);
					GPS_step++;
					break;
				// revised version thx to Christopher Barnes
				case 6: // Payload data read...
					// We need to process the data byte before we check the number of bytes so far
					UBX_buffer[UBX_payload_counter] = data;
					checksum(data);
					UBX_payload_counter++;
					if (UBX_payload_counter < UBX_payload_length_hi) {
						// We stay in this state until we reach the payload_length
					} else {
						GPS_step++; // payload_length reached - next byte is checksum
					}
					break;
				case 7:
					UBX_ck_a=data;	 // First checksum byte
					GPS_step++;
					break;
				case 8:
					UBX_ck_b=data;	 // Second checksum byte
					// We end the GPS read...
					if((ck_a == UBX_ck_a) && (ck_b == UBX_ck_b)){ // Verify the received checksum with the generated checksum..
						GPS_join_data();							 // Parse the new GPS packet
						GPS_timer = millis(); //Restarting timer...
					}
					
					// Variable re-initialization
					GPS_step = 0;
					UBX_payload_counter = 0;
					ck_a = 0;
					ck_b = 0;
					break;
			}
		}
	}
	
	if((millis() - GPS_timer) > 2000){
		digitalWrite(12, LOW);	//If we don't receive any byte in two seconds turn off gps fix LED... 
		GPS_fix = BAD_GPS;
		GPS_update = GPS_NONE;

		if((millis() - GPS_timer) > 10000){
			GPS_fix = FAILED_GPS;
			GPS_timer = millis();
			Serial.println("gpsFailure... ");
			//reinit the GPS Modules
		}
	}
}

/****************************************************************
 * 
 ****************************************************************/
void GPS_join_data()
{
	int j; // our Byte Offset

	if(UBX_class == 0x01) 
	{
		//Checking the UBX ID
		switch(UBX_id){
		
		case 0x02: //ID NAV-POSLLH 
			if(GPS_fix == VALID_GPS){
				j=0;
				iTOW = join_4_bytes(&UBX_buffer[j]);
				
				j = 4;
				current_loc.lng = join_4_bytes(&UBX_buffer[j]);
	
				j = 8;
				current_loc.lat = join_4_bytes(&UBX_buffer[j]);
	
				j = 16;
				current_loc.alt = join_4_bytes(&UBX_buffer[j])/10; //alt_MSL
				
				GPS_update |= GPS_POSITION;
			}
			break;
			
		case 0x03://ID NAV-STATUS 
			//Serial.print("NAV-STATUS: ");
			//Serial.print("UBX_buffer ");
			//Serial.println(UBX_buffer[4],DEC);
			
			if(UBX_buffer[4] >= 0x03){
				GPS_fix = VALID_GPS; //valid position
				digitalWrite(12,HIGH);
			} else {
				GPS_fix = BAD_GPS; //invalid position
				digitalWrite(12,LOW);
			}
			break;

		case 0x12:// ID NAV-VELNED 
			if(GPS_fix == VALID_GPS){
				/* not used
				j=16;
				speed_3d = join_4_bytes(&UBX_buffer[j]); // m/s
				*/
				j=20;
				ground_speed = join_4_bytes(&UBX_buffer[j]); // Ground speed 2D			
	
				if (ground_speed >= 120){
					j=24;
					ground_course = join_4_bytes(&UBX_buffer[j]) / 1000; // Heading 2D
				}
				
				GPS_update |= GPS_HEADING;
			}
			break; 
		}
	}
}

 // Join 4 bytes into a long
 // -------------------------
int32_t join_4_bytes(byte Buffer[])
{
	longUnion.byte[0] = *Buffer;
	longUnion.byte[1] = *(Buffer+1);
	longUnion.byte[2] = *(Buffer+2);
	longUnion.byte[3] = *(Buffer+3);
	return(longUnion.dword);
}

void checksum(byte data)
{
	ck_a += data;
	ck_b += ck_a; 
}


void wait_for_GPS_fix(void)//Wait GPS fix...
{
	Serial.println(" ");
	Serial.println("Wait for GPS");
	GPS_update 	= GPS_NONE;
	GPS_fix 	= BAD_GPS;
	
	do{
		for(int c=0; c<=20; c++){
			decode_gps();
			digitalWrite(12,LOW);
			delay(25);
			digitalWrite(12,HIGH);
			delay(25);
		}
		if(GPS_fix == BAD_GPS){
			Serial.println("Still Waiting: No Valid Fix");
		}
	} while(GPS_fix >= BAD_GPS && GPS_update == GPS_NONE);
}
#endif

