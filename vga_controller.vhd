library ieee;
use ieee.std_logic_1164.all;

entity vga_controller is
	generic (
		-- 1920x1200
		-- h_sync_time : integer := 208;
		-- h_back_porch_time : integer := 336;
		-- h_draw_time : integer := 1920;
		-- h_front_porch_time : integer := 128;
		-- h_sync_polarity : std_logic := '0';
		-- v_sync_time : integer := 3;
		-- v_back_porch_time : integer := 38;
		-- v_draw_time : integer := 1200;
		-- v_front_porch_time : integer := 1;
		-- v_sync_polarity : std_logic := '1';

		-- 1920x1080
		h_sync_time : integer := 207;
		h_back_porch_time : integer := 326;
		h_draw_time : integer := 1920;
		h_front_porch_time : integer := 119;
		h_sync_polarity : std_logic := '1';
		v_sync_time : integer := 3;
		v_back_porch_time : integer := 32;
		v_draw_time : integer := 1080;
		v_front_porch_time : integer := 1;
		v_sync_polarity : std_logic := '1'
	);
	port (
		pixel_clk : in std_logic; --pixel clock at frequency of VGA mode being used, 172MHz for 1920x1080
		reset_n : in std_logic; --active low asycnchronous reset
		h_sync : out std_logic; --horiztonal sync pulse
		v_sync : out std_logic; --vertical sync pulse
		display_enable : out std_logic; --display enable ('1' - display time, '0' - blanking time), necessary to avoid artifacts
		current_pixel_h : out integer;
		current_pixel_v : out integer --vertical pixel coordinate
	);
end vga_controller;

architecture behavior of vga_controller is
	constant h_period : integer := h_sync_time + h_back_porch_time + h_draw_time + h_front_porch_time; -- total horizontal number of pixel clocks 
	constant v_period : integer := v_sync_time + v_back_porch_time + v_draw_time + v_front_porch_time; -- total vertival number of horizotal lines
begin

	main : process (pixel_clk, reset_n)
		variable h_count : integer range 0 to h_period - 1 := 0;
		variable v_count : integer range 0 to v_period - 1 := 0;
	begin
		if (reset_n = '0') then -- reset asserted
			h_count := 0;
			v_count := 0;
			h_sync <= not h_sync_polarity; -- deassert horizontal sync
			v_sync <= not v_sync_polarity; -- deassert vertical sync
			display_enable <= '0'; -- disable display
			current_pixel_h <= 0;
			current_pixel_v <= 0;
		elsif (rising_edge(pixel_clk)) then
			if (h_count < h_period - 1) then --horizontal counter (pixels)
				h_count := h_count + 1;
			else
				h_count := 0;
				if (v_count < v_period - 1) then --veritcal counter (rows)
					v_count := v_count + 1;
				else
					v_count := 0;
				end if;
			end if;
			-- horizontal sync signal
			if (h_count < h_draw_time + h_front_porch_time or h_count >= h_draw_time + h_front_porch_time + h_sync_time) then
				h_sync <= not h_sync_polarity; -- deassert horiztonal sync pulse
			else
				h_sync <= h_sync_polarity; -- assert horiztonal sync pulse
			end if;
			-- vertical sync signal
			if (v_count < v_draw_time + v_front_porch_time or v_count >= v_draw_time + v_front_porch_time + v_sync_time) then
				v_sync <= not v_sync_polarity; -- deassert vertical sync pulse
			else
				v_sync <= v_sync_polarity; -- assert vertical sync pulse
			end if;
			-- set pixel coordinates
			if (h_count < h_draw_time) then -- horiztonal display time
				current_pixel_h <= h_count; -- set horiztonal pixel coordinate
			end if;
			if (v_count < v_draw_time) then -- vertical display time
				current_pixel_v <= v_count; -- set vertical pixel coordinate
			end if;
			-- set display enable output
			if (h_count < h_draw_time and v_count < v_draw_time) then -- display time
				display_enable <= '1'; --enable display
			else -- blanking time
				display_enable <= '0'; -- disable display
			end if;
		end if;
	end process;
end behavior;