/*****************************************
 *****************************************/
void init_ardupilot(void)
{
  pinMode(13,OUTPUT);//LED pin
  
  pinMode(2,INPUT);//Servo input
  pinMode(3,INPUT);//Servo Input 
  pinMode(4,INPUT); //MUX pin
  pinMode(5,INPUT); //Mode pin
  
  digitalWrite(6,HIGH);
  pinMode(6,INPUT); //Remove Before Fly ground
  
  pinMode(7,OUTPUT); //Remove Before Fly input pin
  digitalWrite(7, LOW); //Remove Before Fly Pull Up resistor
  
  pinMode(8,OUTPUT);//Servo throtle
  pinMode(11,OUTPUT);//GPS status
  Init_servos(); 
  //Centering Servos
  pulse_servos(0,0); 
  pulse_servo_0(0);
  
  Analog_Reference(0);//Using external analog reference
  Analog_Init();
  
  #if CALIBRATE_SERVOS == 1
  calibrate_servos();
  #endif
  
  rx_Ch[0]=pulseIn(2, HIGH, 20000); //Reading the radio sticks central position...
  rx_Ch[1]=pulseIn(3, HIGH, 20000); //Reading the radio sticks central position...
  
  if(digitalRead(6) == LOW) //Verify if the "Remove Before Fly" flag is connected... 
  {
    delay(2000);
    init_gps(); //Initializing GPS
    Wait_GPS_Fix();//Wait GPS fix...
    test_servos(); //testing servos
    Load_Settings();//Loading saved settings
    
    #if FAKE_GPS_LOCK == 0
    while(digitalRead(6) == LOW){ //Loops until we remove the safetly flag
    test_servos(); //Testing servos
    for(int c=0; c<=40; c++)
    {  
    decode_gps();  //Decoding GPS
    catch_analogs(); //Reading Analogs
    }
    }//Loop till we remove the safety flag.. 
    #else
    Serial.println("Warning GPS in fake mode!!!!!!");
    delay(2000);
    #endif
    Save_Launch_Parameters_Flagged();
    current_wp=0; //Restarting waypoint position. 
  }
  else
  { 
    fast_init_gps();
    Load_Settings();
    Restore_Launch_Parameters();
  }
  
  Serial.println("");
  Serial.println("Ardupilot!!! V23");
  #if PRINT_WAYPOINTS == 1
  print_waypoints();
  #endif
  #if TEST_THROTTLE == 1
  test_throttle();
  #endif
  
  #if PRINT_EEPROM == 1
  Print_EEPROM();
  #endif
}
/*****************************************************************************
 *****************************************************************************/
void Load_Settings(void)
{
  options=(byte)eeprom_read_byte((byte*)0x00);
  //air_speed_offset=(int)eeprom_read_word((unsigned int*)0x01); //Restoring airspeed bias
  roll_trim=(byte)eeprom_read_byte((byte*)0x03); //You know like the transmitter trims
  pitch_trim=(byte)eeprom_read_byte((byte*)0x04); 
  max_alt= (int)eeprom_read_word((unsigned int*)0x05);
  max_spd=(int)eeprom_read_word((unsigned int*)0x07);
  wp_number=(byte)eeprom_read_byte((byte*)0x09); //Number of waypoints defined.... Go to to Waypoint tab...
  wp_radius=(byte)eeprom_read_byte((byte*)0x0B); //Radius of the waypoint, normally set as 20 meters.
  //alt_hold=(int)eeprom_read_word((unsigned int*)0x16);  
}

void Save_Launch_Parameters_Flagged(void)
{
  launch_alt=alt_MSL;//Storing launch altitude... 
  zero_airspeed();
  current_wp=0;

  eeprom_busy_wait(); 
  eeprom_write_byte((byte*)0x0A,current_wp);

  eeprom_busy_wait(); 
  //eeprom_write_word((unsigned int*)0x01,max_ir);//Saving Infrared Calibration.. air_speed_bias
  eeprom_write_word((unsigned int*)0x01,air_speed_offset);//Saving Airspeed..

  eeprom_busy_wait();
  eeprom_write_word((unsigned int*)0x0C,launch_alt);//Saving home altitude

  eeprom_busy_wait();
  eeprom_write_dword((unsigned long*)0x0E,(long)((float)lat*(float)t7));//Saving home position.

  eeprom_busy_wait();
  eeprom_write_dword((unsigned long*)0x12,(long)((float)lon*(float)t7));

}
/****************************************************************
 ****************************************************************/
void Restore_Launch_Parameters(void)
{
  eeprom_busy_wait();
  air_speed_offset=(int)eeprom_read_word((unsigned int*)0x01);//Restoring airspeed bias
  
  #if REMEMBER_LAST_WAYPOINT_MODE == 1
  current_wp=(int)eeprom_read_byte((byte*)0x0A);
  #endif
  
  eeprom_busy_wait();
  zero_airspeed();
  launch_alt=(int)eeprom_read_word((unsigned int*)0x0C);//Restoring launch altitude from eeprom...  
}
/****************************************************************
 ****************************************************************/
byte Tx_Switch_Status(void) //Return zero when we are in manual mode, return 2 when autopilot mode 0, return 3 when autopilot mode 1...   
{
  #if RADIO_SWITCH_ACTION == 0
  if(digitalRead(4)==HIGH)
  {
    if(digitalRead(5)==HIGH)
      return 0x01; // WP mode 
    else
      return 0x02; // RTL mode
  }
  else
    return 0x00; 
  #endif
  #if RADIO_SWITCH_ACTION == 1
  if(digitalRead(4)==HIGH)
  {
    if(digitalRead(5)==HIGH)
      return 0x02; // RTL mode 
    else
      return 0x01; // wp mode
  }
  else
    return 0x00; 
  #endif
}

/*****************************************************************************
 *****************************************************************************/
float reset(float value)
{
  if(Tx_Switch_Status()==0x00)
    return 0; 
  else
    return value; 
}
/*****************************************************************************
 *****************************************************************************/

void maxis(void)
{
  if(gpsFix == 0x00)
  {
    if(alt_MSL>max_alt)
    {
      max_alt=alt_MSL;
      eeprom_busy_wait(); 
      eeprom_write_word((unsigned int*)0x05,max_alt);
    }

    if(ground_speed>max_spd)
    {
      max_spd=ground_speed;
      eeprom_busy_wait(); 
      eeprom_write_word((unsigned int*)0x07,max_spd);
    }
  }
}
void print_data(void)
{
  static unsigned long timer1=0;
  static byte counter;
  
  if(millis()-timer1 > ATTITUDE_RATE_OUTPUT)
  {   
     digitalWrite(13,HIGH);
    if(counter >= POSITION_RATE_OUTPUT)//If to reapeat every second.... 
    {
      Serial.print("!!!");
      Serial.print("LAT:");
      Serial.print((long)((float)lat*(float)t7));
      Serial.print(",LON:");
      Serial.print((long)((float)lon*(float)t7)); //wp_current_lat
      Serial.print (",SPD:");
      Serial.print(ground_speed);    
      Serial.print(",CRT:");
      Serial.print(climb_rate);
      Serial.print (",ALT:");
      Serial.print(Get_Relative_Altitude());
      Serial.print (",ALH:");
      Serial.print(Hold_Current_Altitude());
      Serial.print (",CRS:");
      Serial.print(ground_course);
      Serial.print (",BER:");
      Serial.print(wp_bearing);
      Serial.print (",WPN:");
      Serial.print((int)last_waypoint);//Actually is the waypoint.
      Serial.print (",DST:");
      Serial.print(wp_distance);
      Serial.print (",BTV:");
      Serial.print(Batt_Volt);
      //Serial.print(read_Ch1());
      Serial.print (",RSP:");
      Serial.print(roll_set_point);
      //Serial.print(read_Ch2());
      Serial.println(",***");
      counter=0;
      
      //Serial.println(refresh_rate);
      refresh_rate=0;
    }
    else
    {
    counter++;
    
    Serial.print("$$$");
    Serial.print("ASP:");
    Serial.print((int)airSpeed());
    Serial.print(",THH:");
    Serial.print((int)throttle_set_point);
    Serial.print (",RLL:");
    Serial.print(get_roll());
    //Serial.print(Roll);
    Serial.print (",PCH:");
    Serial.print(get_pitch());
    
    Serial.print (",STT:");
    Serial.print((int)Tx_Switch_Status());
    /*
    Serial.print(",");
    Serial.print ("rER:");
    Serial.print((int)roll_set_point);
    Serial.print (",Mir:");
    Serial.print(max_ir);
    Serial.print(",");
    Serial.print ("CH1:");
    Serial.print(read_Ch1()/16);
    Serial.print(",");
    Serial.print ("CH2:");
    Serial.print(read_Ch2()/16);
    Serial.print (",PSET:");
    Serial.print(pitch_set_point);
    */
    Serial.println(",***");
    }
    timer1=millis(); 
    digitalWrite(13,LOW);
  } 
}
