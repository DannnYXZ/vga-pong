library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_rgb_stream is
	generic (
		screen_w : integer := 1920;
		screen_h : integer := 1080;
		paddle_w : integer := 15;
		paddle_h : integer := 120;
		paddle_offset : integer := 45; -- from vertical borders
		ball_d : integer := 32; -- diameter
		paddle_velocity_abs : integer := 3;
		ball_velocity_abs : integer := 2
	);
	port (
		display_enable : in std_logic; --display enable ('1' = display time, '0' = blanking time)
		pixel_h : in integer;
		pixel_v : in integer;
		game_clk : in std_logic; --game ticks, must be slow
		player_l_btn_up : in std_logic;
		player_l_btn_down : in std_logic;
		player_r_btn_up : in std_logic;
		player_r_btn_down : in std_logic;

		red : out std_logic_vector(7 downto 0); -- left more digits for future DAC support
		green : out std_logic_vector(7 downto 0);
		blue : out std_logic_vector(7 downto 0)
	);
end vga_rgb_stream;

architecture behavior of vga_rgb_stream is

	type ivec2 is record
		x : integer;
		y : integer;
	end record;
	type i_arr is array(natural range <>) of integer;
	type state is (idle, play);

	function max(a, b : integer) return integer is
	begin
		if a > b then
			return a;
		else
			return b;
		end if;
	end function;

	function iff(condition : std_logic; a, b : integer) return integer is
	begin
		if condition = '1' then
			return a;
		else
			return b;
		end if;
	end function;

	function "+"(a, b : ivec2) return ivec2 is
	begin
		return (x => a.x + b.x, y => a.y + b.y);
	end function;

	function "-"(a, b : ivec2) return ivec2 is
	begin
		return (x => a.x - b.x, y => a.y - b.y);
	end function;

	function in_box(p, box_pos, box_size : ivec2) return boolean is
		variable uv, d : ivec2;
	begin
		uv := (x => p.x - box_pos.x, y => p.y - box_pos.y); -- change of basis to the box up left
		return (uv.x > 0) and (uv.y > 0) and (uv.x < box_size.x) and (uv.y < box_size.y);
	end function;

	function box_intersect(b1_tl, b1_br, b2_tl, b2_br : ivec2) return boolean is
		variable uv, d : ivec2;
	begin
		return (b1_br.x >= b2_tl.x) and (b1_tl.x <= b2_br.x) and (b1_br.y >= b2_tl.y) and (b1_tl.y <= b2_br.y);
	end function;

	-- out of combinational nodes :( 6272 max but this works
	-- function in_number(p, number_tl : ivec2; number : integer) return boolean is 
	-- 	constant cell_d : integer := 20;

	-- 	variable font_digit, digit, n : integer;
	-- 	variable uv, font_uv, char_basis : ivec2;
	-- 	variable font : i_arr(0 to 9) := (15324974, 14815428, 32553487, 16265743, 17332785, 33061951, 15252542, 8659487, 15252014, 15235630);
	-- 	variable char_digits : std_logic_vector(31 downto 0);
	-- begin
	-- 	n := number;
	-- 	char_basis := number_tl;
	-- 	for i in 0 to 0 loop
	-- 		digit := n mod 10; -- last number digit
	-- 		n := n / 10;
	-- 		char_digits := std_logic_vector(to_unsigned(font(digit), char_digits'length)); -- digit 5x5 representation
	-- 		uv := p - char_basis;
	-- 		font_uv := (x => uv.x/cell_d, y => uv.y/cell_d);
	-- 		if (font_uv.x < 0 or font_uv.y < 0 or font_uv.x >= 5 or font_uv.y >= 5) then
	-- 			next;
	-- 		end if;
	-- 		if (char_digits(5 * font_uv.y + font_uv.x) = '1') then
	-- 			return true;
	-- 		end if;
	-- 		char_basis.x := char_basis.x - cell_d * 6; -- move basis to the left
	-- 	end loop;
	-- 	return false;
	-- end function;

	constant ball_size : ivec2 := (x => ball_d, y => ball_d);
	constant paddle_size : ivec2 := (x => paddle_w, y => paddle_h);
	shared variable pixel : ivec2; -- current screen pixel position
	shared variable game_state : state := idle;
	shared variable game_tick_timer : integer := 1;
	shared variable score : ivec2 := (x => 0, y => 0); -- x - left player score, y - right
	shared variable ball_pos : ivec2 := (x => screen_w/2, y => screen_h/2);
	shared variable ball_velocity : ivec2 := (x => - ball_velocity_abs, y => ball_velocity_abs);
	shared variable paddle_l_pos : ivec2 := (x => paddle_offset, y => (screen_h - paddle_h)/2);
	shared variable paddle_r_pos : ivec2 := (x => screen_w - paddle_offset - paddle_w, y => (screen_h - paddle_h)/2);
begin

	pong_game : process (game_clk)
		variable next_pos : ivec2;
		variable paddle_l_velocity, paddle_r_velocity : integer;
	begin
		if (rising_edge(game_clk)) then
			-- get paddles input
			paddle_l_velocity := paddle_velocity_abs * iff(player_l_btn_up, iff(player_l_btn_down, 0, 1), -1);
			paddle_r_velocity := paddle_velocity_abs * iff(player_r_btn_up, iff(player_r_btn_down, 0, 1), -1);
			-- finit state machine
			if (game_state = idle) then
				ball_pos := (x => (screen_w - ball_d)/2, y => (screen_h - ball_d)/2);
				paddle_l_pos.y := (screen_h - paddle_h)/2;
				paddle_r_pos.y := (screen_h - paddle_h)/2;
				if ((paddle_l_velocity > 0) or (paddle_r_velocity > 0)) then
					game_state := play;
				end if;
			elsif (game_state = play) then
				game_tick_timer := game_tick_timer - 1;
				if (game_tick_timer = 0) then
					game_tick_timer := 1720000/5; -- using vga pixel clock
					-- move paddles
					paddle_l_pos.y := paddle_l_pos.y + paddle_l_velocity;
					paddle_r_pos.y := paddle_r_pos.y + paddle_r_velocity;
					-- paddles-walls collision
					paddle_l_pos.y := max(paddle_l_pos.y, 0);
					paddle_r_pos.y := max(paddle_r_pos.y, 0);
					if (paddle_l_pos.y + paddle_h > screen_h) then
						paddle_l_pos.y := screen_h - paddle_h;
					end if;
					if (paddle_r_pos.y + paddle_h > screen_h) then
						paddle_r_pos.y := screen_h - paddle_h;
					end if;
					-- move ball
					ball_pos := ball_pos + ball_velocity;
					if (ball_pos.y + ball_size.y > screen_h or ball_pos.y < 0) then
						-- bottom or top wall hit
						ball_velocity.y := - ball_velocity.y;
					elsif (ball_pos.x < 0) then
						-- left wall hit
						score.x := score.x + 1;
						game_state := idle;
					elsif (ball_pos.x + ball_size.x > screen_w) then
						-- right wall hit
						score.y := score.y + 1;
						game_state := idle;
					elsif (box_intersect(ball_pos, ball_pos + ball_size, paddle_l_pos, paddle_l_pos + paddle_size)) then
						-- ball collides with the left paddle
						ball_velocity.x := - ball_velocity.x;
					elsif (box_intersect(ball_pos, ball_pos + ball_size, paddle_r_pos, paddle_r_pos + paddle_size)) then
						-- ball collides with the right paddle
						ball_velocity.x := - ball_velocity.x;
					end if;
				end if;
			end if;
		end if;
	end process;

	render : process (display_enable, pixel_v, pixel_h)
	begin
		pixel := (x => pixel_h, y => pixel_v);
		if (display_enable = '1') then --display time
			if (in_box(pixel, ball_pos, ball_size)) then -- render ball
				red <= (others => '1');
				green <= (others => '1');
				blue <= (others => '1');
			elsif (in_box(pixel, paddle_l_pos, paddle_size)) then -- render left paddle
				red <= (others => '1');
				green <= (others => '0');
				blue <= (others => '1');
			elsif (in_box(pixel, paddle_r_pos, paddle_size)) then -- render right paddle
				red <= (others => '0');
				green <= (others => '1');
				blue <= (others => '1');
			elsif (in_box(pixel, (x => screen_w/2 - 5, y => 0), (x => 10, y => screen_h))) then -- render middle line
				red <= (others => '1');
				green <= (others => '1');
				blue <= (others => '1');
			else
				red <= (others => '0');
				green <= (others => '0');
				blue <= (others => '0');
				-- render score, out of combinational nodes :( 6272 max
				-- if (in_number(pixel, (x => screen_w/4, y => 10), score.x)) then
				-- 	red <= (others => '1');
				-- 	green <= (others => '1');
				-- 	blue <= (others => '1');
				-- elsif (in_number(pixel, (x => screen_w * 3/4, y => 10), score.y)) then
				-- 	red <= (others => '1');
				-- 	green <= (others => '1');
				-- 	blue <= (others => '1');
			end if;
		else --blanking time, to avoid artifacts
			red <= (others => '0');
			green <= (others => '0');
			blue <= (others => '0');
		end if;
	end process;

end behavior;